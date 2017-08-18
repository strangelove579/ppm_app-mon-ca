
<%@ page import="com.niku.union.persistence.connection.ConnectionContext" %>
<%@ page import="com.niku.union.security.DefaultSecurityIdentifier" %>
<%@ page import="com.niku.union.security.UserSessionController" %>
<%@ page import="com.niku.union.security.UserSessionControllerFactory" %>
<%@ page import="com.niku.xql2.jdbc.JDBCSession" %>
<%@ page import="java.sql.*" %>
<%@ page import="com.crystaldecisions.sdk.framework.*" %>
<%@ page import="com.crystaldecisions.sdk.plugin.desktop.server.IServerBase" %>
<%@ page import="com.businessobjects.sdk.plugin.desktop.common.*" %>
<%@ page import="com.niku.reporting.schema.ReportingServerUserSession" %>
<%@ page import="com.niku.reporting.bo.BOReporting" %>
<%@ page import="com.niku.reporting.ReportingProperties" %>
<%@ page import="com.crystaldecisions.sdk.exception.SDKException" %>
<%@ page import="com.crystaldecisions.sdk.occa.infostore.*" %>

<%@ page import = "com.crystaldecisions.sdk.exception.*"%>
<%@ page import = "com.crystaldecisions.sdk.occa.infostore.*"%>
<%@ page import = "com.crystaldecisions.sdk.plugin.desktop.server.*"%>
<%@ page import = "com.crystaldecisions.sdk.occa.infostore.CePropertyID"%>
<%@ page import = "com.crystaldecisions.sdk.occa.enadmin.*"%>
<%@ page import = "com.crystaldecisions.sdk.plugin.admin.cmsadmin.*"%>
<%@ page import = "com.crystaldecisions.sdk.plugin.desktop.common.*"%>
<%@ page import = "com.crystaldecisions.sdk.occa.security.*"%>

<%@ taglib uri="http://java.sun.com/jsp/jstl/core" prefix="c" %>
<%@ taglib uri="http://java.sun.com/jsp/jstl/functions" prefix="fn" %>
<%

// BO Server Status
// version 1.1 - Shawn Moore
// January 22, 2013
// Updated 6/13/13  John Achee,   Changed Max Jobs counts such that it is an aggregate of any/all
//                                Adaptive or Crystal Job server regardless of service name and
//                                instead filtering on SI_SERVER_DESCRIPTOR attribute

  //////////////////////////////////
  // Get the status of the BO Queue

  int crystal_queue_length = -1;
  int max_crystal_jobs = 0;
  int webi_queue_length = -1;
  int max_webi_jobs = 0;

  // i.e. si_schedule_status 0 is running, si_schedule_status 9 is pending.
	String crystal_query = 	"SELECT SI_NAME, SI_CREATION_TIME, SI_OWNER, SI_SCHEDULE_STATUS " +
													"FROM CI_INFOOBJECTS WHERE SI_INSTANCE = 1 AND SI_SCHEDULE_STATUS in (0, 9) " +
													"AND SI_KIND = ";

	String server_query = "SELECT * FROM CI_SYSTEMOBJECTS WHERE SI_KIND = 'Server' and si_description = ";
	IEnterpriseSession eSession = null;

  try
  {
		// Check Crystal Reports Server

		// Declare Variables
		IInfoObjects boInfoObjects=null;
		SDKException failure = null;

		IServer currentServer = null;
		ICMSAdmin cmsAdmin = null;
		IServerGeneralMetrics serverMetrics = null;

  	String username = ReportingProperties.getInstance().getUsername();
		BOReporting reporting = new BOReporting();
    ReportingServerUserSession userSession = reporting.login( username );

    eSession = (IEnterpriseSession) userSession.getSession();
    IInfoStore boInfoStore = (IInfoStore) eSession.getService( "InfoStore" );

    boInfoObjects = boInfoStore.query("Select * From CI_SYSTEMOBJECTS Where SI_PROGID='CrystalEnterprise.Server'");

    out.println ("<HR><B>Servers Status</B><BR>");
    for (int k=0;k<boInfoObjects.getResultSize();k++)
    {
    	currentServer = (IServer) boInfoObjects.get(k);
      //Display the server information
      out.println ("Server: " + currentServer.getName() + ", ");
      out.println ("Enabled: " + !currentServer.isDisabled() + ", ");
      out.println("Running: " + currentServer.isAlive()+ "<BR>");
		}

    boInfoObjects = boInfoStore.query("Select * From CI_SYSTEMOBJECTS Where SI_PROGID='CrystalEnterprise.Server' and SI_DESCRIPTION='Central Management Server'");
  	currentServer = (IServer) boInfoObjects.get(0);

    out.println ("<HR><B>General metrics</B><BR>");
    //retrieve and display Server metrics
    serverMetrics = currentServer.getServerGeneralAdmin();
    out.println ("CPU: " + serverMetrics.getCPU()+"<BR>");
    out.println ("CPU count: " + serverMetrics.getCPUCount()+"<BR>");
    out.println ("Current time: " + serverMetrics.getCurrentTime()+"<BR>");
    out.println ("Server start time: " + serverMetrics.getStartTime()+"<BR>");
    out.println ("Available disk space: " + (Math.round(serverMetrics.getDiskSpaceAvailable()/(1024*1024*102.4))/10.0) + " GB<BR>");
    out.println ("Total disk space: " + (Math.round(serverMetrics.getDiskSpaceTotal()/(1024*1024*102.4))/10.0) + " GB<BR>");
    out.println ("Total Memory: " + (Math.round(serverMetrics.getMemory()/(102.4*1024))/10.0) + " GB<BR>");
    out.println ("Operating system: " + serverMetrics.getOperatingSystem()+"<BR>");
    out.println ("Server Version: " + serverMetrics.getVersion()+"<BR><BR>");

		out.println ("<HR><B>Queue metrics</B><BR>");



       // Added 6/13/13, to get a complete full max jobs count across all crystal and webi job servers

	String crystaljobserver_query  = "SELECT  * FROM CI_SYSTEMOBJECTS WHERE SI_KIND = 'Server' AND SI_DISABLED = 0 AND SI_SERVER_DESCRIPTOR like 'jobserver.CrystalEnterprise.Report' and SI_NAME like '%Crystal%'";
	IInfoObjects rServer = boInfoStore.query(crystaljobserver_query);

	for (int j=0;j<rServer.getResultSize();j++) {


		IServerBase iServer = (IServerBase) rServer.get(j);
		IConfiguredContainer icontainer = iServer.getContainer();
		IActualConfigProperties actualConfig = icontainer.getActualConfigProps();
		IActualConfigProperty prop = actualConfig.getProp("maxJobs");
		Integer maxJobsInteger = (Integer) prop.getValue();
                max_crystal_jobs += maxJobsInteger.intValue();
                                

	}

	String adaptivejobserver_query = "SELECT  * FROM CI_SYSTEMOBJECTS WHERE SI_KIND = 'Server' AND SI_DISABLED = 0 AND SI_SERVER_DESCRIPTOR like 'jobserver.CrystalEnterprise.JavaScheduling' and SI_NAME like '%Adaptive%'";
	rServer = boInfoStore.query(adaptivejobserver_query);

	for (int j=0;j<rServer.getResultSize();j++) {


		IServerBase iServer = (IServerBase) rServer.get(j);
		IConfiguredContainer icontainer = iServer.getContainer();
		IActualConfigProperties actualConfig = icontainer.getActualConfigProps();
		IActualConfigProperty prop = actualConfig.getProp("maxJobs");
		Integer maxJobsInteger = (Integer) prop.getValue();
		max_webi_jobs += maxJobsInteger.intValue();

	}
    
    // Get Crystal Reports queue depth

    IInfoObjects oInfoObjects = (IInfoObjects) boInfoStore.query(crystal_query + "'CrystalReport'");
    crystal_queue_length      = oInfoObjects.getResultSize();

	// Get Webi Reports queue depth

    oInfoObjects      = (IInfoObjects) boInfoStore.query(crystal_query + "'Webi'");
    webi_queue_length = oInfoObjects.getResultSize();



    out.println ("Current Pending/Runnning Crystal Jobs:  " + crystal_queue_length + "<BR>");
    out.println ("Maximum Concurrent Crystal Jobs:  " + max_crystal_jobs+"<BR>");
    out.println ("Current Pending/Runnning WEBI Jobs:  " + webi_queue_length + "<BR>");
    out.println ("Maximum Concurrent WEBI Jobs:  " + max_webi_jobs + "<BR>");
  }
  catch( SDKException se )
  {
  	    out.println("Exception occurred while checking the server: " + se.getMessage());
  }
  finally
  {
  	if (eSession != null)
  	{
  		eSession.logoff();
    }
  }



%>

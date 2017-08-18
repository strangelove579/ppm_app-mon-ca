<%@ page import="com.niku.union.persistence.connection.ConnectionContext" %>
<%@ page import="com.niku.union.security.DefaultSecurityIdentifier" %>
<%@ page import="com.niku.union.security.UserSessionController" %>
<%@ page import="com.niku.union.security.UserSessionControllerFactory" %>
<%@ page import="com.niku.xql2.jdbc.JDBCSession" %>
<%@ page import="java.sql.*" %>
<%@ taglib uri="http://java.sun.com/jsp/jstl/core" prefix="c" %>
<%@ taglib uri="http://java.sun.com/jsp/jstl/functions" prefix="fn" %>
<!-- Monitor.jsp

  version = 1.01
  Last Updated = 2013/02/08
  Author = Sean Harp

  Changelog:

  2013/02/08: Fixed NJS_HEARTBEAT to return single min heartbeat value
  2013/03/11: Fixed (again) NJS_HEARTBEAT query to return a single value (previously accidentally omitted)

-->
<%
  Connection conn = null;
  int databaseLogin = 1;
  long start = 0;
  long stop = 0;
  String userName = "monitor_admin";

  try
  {
    // Try to get a database connection, we'll use it later on.
    try
    {

      ConnectionContext context = ConnectionContext.getContext("Niku");
      conn = context.getConnection( ConnectionContext.AUTOCOMMIT_MODE );

      // Attempt a db conn check
      String healthSqlQuery = "select 1 AS HEALTH from dual";
      Statement healthStmt = conn.createStatement();
      ResultSet healthRs = healthStmt.executeQuery(healthSqlQuery);
      while (healthRs.next()) {
        int health = healthRs.getInt("HEALTH");
      }
      healthRs.close();
      healthStmt.close();
    }
    catch (Exception e)
    {
      databaseLogin = 0;
    }

    // Initialize all responses to failure
    int loginSuccess = 0;
    long login_time = -1;
    int njs_heartbeat = -1;
    int pe_heartbeat = -1;
    int last_ts_s = -1;
    int is_rollover_date = -1;


    if (databaseLogin == 1)
    {

      // Determine which user we should attempt to log in as
      String sqlQuery = "select user_name from cmn_sec_users where id in (1,9) order by id desc";
      PreparedStatement stmt = conn.prepareStatement( sqlQuery );
      ResultSet rs = stmt.executeQuery();
      if (rs.next()) {
        userName = rs.getString("USER_NAME");
      }
      rs.close();
      stmt.close();

      // Attempt to perform a login as monitor_admin
      start = System.currentTimeMillis();
      loginSuccess = 1;
      try
      {
        DefaultSecurityIdentifier secId = new DefaultSecurityIdentifier();
        UserSessionController userCtl = UserSessionControllerFactory.getInstance();
        userCtl.init(userName, secId);
        String loginSession = secId.getSessionId();
        userCtl.delete(loginSession);
      }
      catch (Exception e)
      {
        loginSuccess = 0;
      }
      stop = System.currentTimeMillis();
      login_time = stop - start;


      // Get the status of the Job Scheduler
      try
      {
        sqlQuery = "select round((sysdate - max(njs_heart_beat))*60*60*24,0) NJS_HEARTBEAT_AGE " +
          "FROM NJS_MONITOR " +
          "WHERE LAST_UPDATED_DATE >= trunc(sysdate) ";
        stmt = conn.prepareStatement( sqlQuery );
        rs = stmt.executeQuery();
        if (rs.next()) {
          njs_heartbeat = rs.getInt("NJS_HEARTBEAT_AGE");
        }
        rs.close();
        stmt.close();
      }
      catch (Exception e)
      {
        njs_heartbeat = -1;
      }

      // Get the status of the Process Engine (delivered messages)
      sqlQuery = "select round((sysdate - max(heart_beat))*60*60*24,0) PE_HEARTBEAT_AGE from bpm_run_process_engines";
      stmt = conn.prepareStatement( sqlQuery );
      rs = stmt.executeQuery();
      if (rs.next()) {
        pe_heartbeat = rs.getInt("PE_HEARTBEAT_AGE");
      }
      rs.close();
      stmt.close();

      // Get the most recently updated time slice request
      sqlQuery = "select (sysdate - max(request_completed_date))*24*60*60 as LAST_TS_S FROM PRJ_BLB_SLICEREQUESTS";
      stmt = conn.prepareStatement( sqlQuery );
      rs = stmt.executeQuery();
      if (rs.next()) {
        last_ts_s = rs.getInt("LAST_TS_S");
      }
      rs.close();
      stmt.close();

      // Get the most recently updated time slice request
      sqlQuery = "select count(*) as IS_ROLLOVER_DATE from prj_blb_slicerequests where trunc(sysdate) = trunc(expiration_date)";
      stmt = conn.prepareStatement( sqlQuery );
      rs = stmt.executeQuery();
      if (rs.next()) {
        is_rollover_date = rs.getInt("IS_ROLLOVER_DATE");
      }
      rs.close();
      stmt.close();



      conn.close();

    }

    pageContext.setAttribute("db_login", databaseLogin, PageContext.REQUEST_SCOPE);
    pageContext.setAttribute("login_time", login_time, PageContext.REQUEST_SCOPE);
    pageContext.setAttribute("login_success", loginSuccess, PageContext.REQUEST_SCOPE);
    pageContext.setAttribute("njs_heart", njs_heartbeat, PageContext.REQUEST_SCOPE);
    pageContext.setAttribute("pe_heart", pe_heartbeat, PageContext.REQUEST_SCOPE);
    pageContext.setAttribute("last_ts_s", last_ts_s, PageContext.REQUEST_SCOPE);
    pageContext.setAttribute("is_rollover_date", is_rollover_date, PageContext.REQUEST_SCOPE);
  }
  catch (Exception e)
  {
  }
  finally {
    try {
      if (conn != null )
      {
        conn.close();
      }
    }
    catch ( Exception e ) {
    }
  }

%>
DB_LOGIN=<c:out value="${db_login}"/>
LOGIN_SUCCESS=<c:out value="${login_success}"/>
LOGIN_TIME_MS=<c:out value="${login_time}"/>
NJS_HEARTBEAT_S=<c:out value="${njs_heart}"/>
PE_HEARTBEAT_S=<c:out value="${pe_heart}"/>
LAST_TIMESLICE_S=<c:out value="${last_ts_s}"/>
IS_TS_ROLLOVER_DATE=<c:out value="${is_rollover_date}"/>

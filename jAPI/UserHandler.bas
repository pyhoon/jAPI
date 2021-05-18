B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=8.1
@EndOfDesignText@
'Handler class
Sub Class_Globals
	Dim Request As ServletRequest
	Dim Response As ServletResponse
	Dim pool As ConnectionPool
End Sub

Public Sub Initialize

End Sub

Sub Handle(req As ServletRequest, resp As ServletResponse)
	Request = req
	Response = resp
	Dim elements() As String = Regex.Split("/", req.RequestURI)
	If elements.Length > Main.MAX_ELEMENTS Or elements.Length = 0 Then
		Response.SendError(500, "Unknown method")
		Return
	Else If elements.Length - 1 = Main.ELEMENT_CONTROLLER Then
		Dim settings As Map = Utility.ReadSettings
		settings.Put("ROOT_URL", Main.ROOT_URL)
		settings.Put("ROOT_PATH", Main.ROOT_PATH)
		Dim strMain As String = Utility.ReadTextFile("main.html")
		Dim strView As String = Utility.ReadTextFile("user.html")
		strMain = Utility.BuildView(strMain, strView)
		strMain = Utility.BuildHtml(strMain, settings)
		Utility.ReturnHTML(strMain, Response)
		Return
	End If

	Dim ActionList As List
	ActionList.Initialize2(Array As String("register", "activate", "login", "getapikey", "gettoken", "getprofile", "view", "update"))
	If ActionList.IndexOf(elements(Main.ELEMENT_ACTION)) > -1 Then
		OpenConnection
	End If

	Select elements(Main.ELEMENT_ACTION)
		Case "connect"
			Utility.ReturnConnect(Response)
		Case "register"
			Register
		Case "activate"
			'If elements.Length < Main.MAX_ELEMENTS Then Return
			If elements.Length - 1 = Main.ELEMENT_ID Then
				Activate(elements(Main.ELEMENT_ID))
			Else
				Activate("")
			End If
		Case "login"
			Login
		Case "getapikey"
			GetApiKey
		Case "gettoken"
			GetToken
		Case "getprofile"
			GetProfile
		Case "view"
			'If elements.Length < Main.MAX_ELEMENTS Then Return
			If elements.Length - 1 = Main.ELEMENT_ID Then
				Select elements(Main.ELEMENT_ID)
					Case "all"
						View("all")
					Case Else
						View(elements(Main.ELEMENT_ID))
				End Select
			Else
				Response.SendError(500, "Unknown action")
			End If
		Case "update"
			Update
		Case Else
			Response.SendError(500, "Unknown action")
			Return
	End Select
	
	If ActionList.IndexOf(elements(Main.ELEMENT_ACTION)) > -1 Then
		CloseConnection
	End If
End Sub

Sub RequestData As Map
	Try
		Dim data As Map
		Dim ins As InputStream = Request.InputStream
		Dim tr As TextReader
		tr.Initialize(ins)
		Dim json As JSONParser
		json.Initialize(tr.ReadAll)
		data = json.NextObject
	Catch
		LogDebug("[User/RequestData] " & LastException)
	End Try
	Return data
End Sub

Sub OpenConnection
	Try
		Dim config As Map = Utility.ReadConfig
		pool.Initialize(config.Get("DriverClass"), _
		config.Get("JdbcUrl"), _
		config.Get("User"), _
		config.Get("Password"))		
		
		Dim jo As JavaObject = pool
		Dim MaxPoolSize As Int = config.Get("MaxPoolSize")
		jo.RunMethod("setMaxPoolSize", Array(MaxPoolSize))
	Catch
		LogDebug(LastException)
	End Try
End Sub

Sub CloseConnection
	If pool.IsInitialized Then pool.ClosePool
End Sub

Sub WriteErrorLog(Module As String, Message As String)
	Dim con As SQL = pool.GetConnection
	Try
		Dim strSQL As String = $"INSERT
		INTO tbl_error
		(error_text)
		SELECT ?"$
		con.ExecNonQuery2(strSQL, Array As String("[" & Module & "]" & Message))
	Catch
		LogDebug(LastException)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub WriteUserLog(log_view As String, log_type As String, log_text As String, Log_User As String)
	Dim con As SQL = pool.GetConnection
	Try
		Dim strSQL As String = $"INSERT INTO tbl_users_log
		(log_view,
		log_type,
		log_text,
		log_user)
		SELECT ?, ?, ?, ?"$
		con.ExecNonQuery2(strSQL, Array As String(log_view, log_type, log_text, Log_User))
	Catch
		Dim msg_text As String = "[Exception] " & LastException
		WriteErrorLog("WriteUserLog", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub Register
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("user/register", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		Dim eml As String = Map1.Get("eml")
		Dim pwd As String = Map1.Get("pwd")
		Dim name As String = Map1.Get("name")
				
		If eml = "" Or pwd = "" Or name = "" Then
			msg_text = "[Not set]"
			WriteUserLog("user/register", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		
		Dim strSQL As String = $"SELECT
		user_id
		FROM tbl_users
		WHERE user_email = ?"$
		Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(eml))
		If result.NextRow Then
			msg_text = "[Email Used] " & eml
			WriteUserLog("user/register", "fail", msg_text, 0)
			Utility.ReturnError("Error-Email-Used", Response)
			con.Close
			Return
		Else
			Dim salt As String = Utility.MD5(Rnd(100001, 999999))
			Dim hash As String = Utility.MD5(pwd & salt)
			Dim code As String = Utility.MD5(salt & eml)
			Dim key As String = Utility.SHA1(hash)
			Dim flag As String = "M"
			
			strSQL = $"INSERT INTO tbl_users
			(user_email,
			user_name,
			user_hash,
			user_salt,
			user_api_key,
			user_activation_code,
			user_activation_flag)
			VALUES (?, ?, ?, ?, ?, ?, ?)"$
			con.ExecNonQuery2(strSQL, Array As String(eml, name, hash, salt, key, code, flag))
			Dim user_id As Int = con.ExecQuerySingleResult("SELECT LAST_INSERT_ID()")
			msg_text = "new user"
			WriteUserLog("user/register", "success", msg_text, user_id)
			SendEmail(name, eml, code)
			Utility.ReturnSuccess("success", Response)
			con.Close
			Return
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("user/register", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub Activate(Code As String)
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Dim strMain As String
	Dim strSQL As String
	Try
		If Code = "" Then
			strMain = $"<h1>Activation</h1>
			<p>Invalid activation code!</p>"$
			Utility.ReturnHTML(strMain, Response)
			con.Close
			Return
		Else If Code = "vhbgroalh90akyyypt0ah3qjo5gpb0bx" Then ' Dummy Code
			strMain = $"<h1>Activation</h1>
			<p>Dummy activation code!</p>"$
			Utility.ReturnHTML(strMain, Response)
			con.Close
			Return
		Else
			strSQL = $"SELECT
			user_id
			FROM tbl_users
			WHERE user_activation_code = ?
			AND user_activation_flag = 'M'"$						
			Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(Code))
			If result.NextRow Then
				' Update flag
				strSQL = $"UPDATE tbl_users SET
				user_activation_flag = 'R',
				user_activated_at = now(),
				user_active = 1
				WHERE user_activation_code = ?
				AND user_activation_flag = 'M'"$
				con.ExecNonQuery2(strSQL, Array As String(Code))
				
				msg_text = Code
				WriteUserLog("user/activate", "success", msg_text, 0)
				strMain = $"<h1>Activation</h1>
				<p>Your account is now activated!</p>"$
				Utility.ReturnHTML(strMain, Response)
				con.Close
				Return
			Else
				msg_text = "[Email Used] "
				WriteUserLog("user/activate", "fail", msg_text, 0)
				strMain = $"<h1>Activation</h1>
				<p>Account Not found!</p>"$
				Utility.ReturnHTML(strMain, Response)
				con.Close
				Return
			End If
		End If
	Catch
		WriteErrorLog("user/activate", "[Exception] " & LastException)
		strMain = $"<h1>Activation</h1>
		<p>An error occured!</p>"$
		Utility.ReturnHTML(strMain, Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub Login
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Dim strSQL As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("user/login", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		Dim eml As String = Map1.Get("eml")
		Dim pwd As String = Map1.Get("pwd")
				
		If eml = "" Or pwd = "" Then
			msg_text = "[Not set]"
			WriteUserLog("user/login", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
			
		strSQL = $"SELECT
		user_id AS `result`,
		'success' AS `message`,
		user_name,
		user_email,
		ifnull(user_location, '') AS user_location,
		ifnull(user_token, '') AS user_token,
		ifnull(user_api_key, '') AS user_api_key,
		user_activation_flag
		FROM tbl_users
		WHERE user_email = ?
		AND user_hash = md5(concat(?, user_salt))"$
	
		Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(eml, pwd))
		If result.NextRow Then
			If result.GetString("user_activation_flag") = "M" Then
				msg_text = "[Not Activated] " & eml
				WriteUserLog("user/login", "fail", msg_text, result.GetInt("result"))
				Utility.ReturnError("Error-Not-Activated", Response)
				con.Close
				Return
			End If
			' Update login status
			strSQL = $"UPDATE tbl_users SET
			user_login_count = user_login_count + 1,
			user_last_login_at = now()
			WHERE user_email = ?"$
			con.ExecNonQuery2(strSQL, Array As String(eml))
			
			Dim Map2 As Map
			Map2.Initialize
			For i = 0 To result.ColumnCount - 1
				If result.GetColumnName(i) = "result" Then
					Map2.Put("result", result.GetInt("result"))
				Else
					Map2.Put(result.GetColumnName(i), result.GetString2(i))
				End If
			Next
			msg_text = eml
			WriteUserLog("user/login", "success", msg_text, result.GetInt("result"))
			Utility.ReturnJSON(Map2, Response)
		Else
			msg_text = "[Not Found/Wrong Password] " & eml
			WriteUserLog("user/login", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Result", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("user/login", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub GetApiKey
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Dim strSQL As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("user/getapikey", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		Dim eml As String = Map1.Get("eml")
		Dim pwd As String = Map1.Get("pwd")
		
		If eml = "" Or pwd = "" Then
			msg_text = "[Not set]"
			WriteUserLog("user/getapikey", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
			
		strSQL = $"SELECT
		user_id AS `result`,
		'success' AS `message`,
		ifnull(user_api_key, '') AS user_api_key
		FROM tbl_users
		WHERE user_email = ?
		AND user_hash = md5(concat(?, user_salt))"$
	
		Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(eml, pwd))
		If result.NextRow Then
			msg_text = "[Existing key] "
			If result.GetString("user_api_key") = "" Then
				Dim apikey As String = Utility.SHA1(Rnd(100001, 999999))
				' Update apikey
				strSQL = $"UPDATE tbl_users SET
				user_api_key = ?,
				user_last_login_at = now(),
				modified_at = now()
				WHERE user_email = ?"$
				con.ExecNonQuery2(strSQL, Array As String(apikey, eml))
				msg_text = "[New key] "
			End If

			Dim Map2 As Map
			Map2.Initialize
			Map2.Put("result", result.GetInt("result"))
			Map2.Put("message", "success")
			Map2.Put("user_api_key", apikey)
			WriteUserLog("user/getapikey", "success", msg_text & eml, result.GetInt("result"))
			Utility.ReturnJSON(Map2, Response)
		Else
			msg_text = "[Not Found] " & eml
			WriteUserLog("user/getapikey", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Result", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("user/getapikey", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub GetToken
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Dim strSQL As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("user/gettoken", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		Dim apikey As String = Map1.Get("key")
		
		If apikey = "" Then
			msg_text = "[Not set]"
			WriteUserLog("user/gettoken", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
			
		strSQL = $"SELECT
		user_id AS `result`,
		'success' AS `message`,
		ifnull(user_token, '') AS user_token
		FROM tbl_users
		WHERE user_api_key = ?"$
	
		Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(apikey))
		If result.NextRow Then
			Dim token As String = result.GetString("user_token")
			msg_text = "[Existing token] "
			If token = "" Then
				Dim newtoken As String = Utility.SHA1(Rnd(100001, 999999))
				' Update token
				strSQL = $"UPDATE tbl_users SET
				user_token = ?,
				user_last_login_at = now(),
				modified_at = now()
				WHERE user_api_key = ?"$
				con.ExecNonQuery2(strSQL, Array As String(newtoken, apikey))
				token = newtoken
				msg_text = "[New token] "
			End If

			Dim Map2 As Map
			Map2.Initialize
			Map2.Put("result", result.GetInt("result"))
			Map2.Put("message", "success")
			Map2.Put("user_token", token)
			WriteUserLog("user/gettoken", "success", msg_text & "key: " & apikey, result.GetInt("result"))
			Utility.ReturnJSON(Map2, Response)
		Else
			msg_text = "[Not Found] " & apikey
			WriteUserLog("user/gettoken", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Result", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("user/gettoken", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub GetProfile
	Dim con As SQL = pool.GetConnection
	Dim result As ResultSet
	Dim msg_text As String
	Dim strSQL As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("user/view", "fail", msg_text, 0)
			Utility.ReturnError("Error-Not-Authorized", Response)
			If con <> Null And con.IsInitialized Then con.Close
			Return
		End If

		Dim token As String = Map1.Get("token")
		LogDebug(token)
		If token = "" Then
			Utility.ReturnError("Error-Not-Authorized", Response)
			If con <> Null And con.IsInitialized Then con.Close
			Return
		End If
		
		' Update last login
		strSQL = $"UPDATE tbl_users SET
				user_last_login_at = now()
				WHERE user_token = ?"$
		con.ExecNonQuery2(strSQL, Array As String(token))
		
		' Check Login session token
		strSQL = $"SELECT
		user_id AS `result`,
		'success' AS `message`,
		user_name,
		user_email,
		ifnull(user_location, '') AS user_location
		FROM tbl_users
		WHERE user_token = ?"$
		result = con.ExecQuery2(strSQL, Array As String(token))
		Dim List2 As List
		List2.Initialize
		Do While result.NextRow
			Dim Map2 As Map
			Map2.Initialize
			For i = 0 To result.ColumnCount - 1
				If result.GetColumnName(i) = "result" Then
					Map2.Put("result", result.GetInt("result"))
				Else
					Map2.Put(result.GetColumnName(i), result.GetString2(i))
				End If
			Next
			List2.Add(Map2)
		Loop
		If List2.Size > 0 Then
			Utility.ReturnJSON2(List2, Response)
		Else
			Utility.ReturnError("Error-Invalid-Token", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("user/getprofile", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub View(id As String)
	Dim con As SQL = pool.GetConnection
	Dim result As ResultSet
	Dim msg_text As String
	Dim strSQL As String	
	Try
		If id = "" Then
			Utility.ReturnError("Error-No-Value", Response)
			If con <> Null And con.IsInitialized Then con.Close
			Return
		End If
		
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("user/view", "fail", msg_text, 0)
			Utility.ReturnError("Error-Not-Authorized", Response)
			If con <> Null And con.IsInitialized Then con.Close
			Return
		End If

		Dim token As String = Map1.Get("token")
		LogDebug(token)
		If token = "" Then
			Utility.ReturnError("Error-Not-Authorized", Response)
			If con <> Null And con.IsInitialized Then con.Close
			Return
		End If
		
		' Check Login session token
		strSQL = "SELECT user_id FROM tbl_users WHERE user_token = ?"
		result = con.ExecQuery2(strSQL, Array As String(token))
		If result.NextRow Then
			strSQL = $"UPDATE tbl_users SET
				user_last_login_at = now()
				WHERE user_token = ?"$
			con.ExecNonQuery2(strSQL, Array As String(token))
			
			' Query users logged in within 10 minutes
			strSQL = $"SELECT
			user_id AS `result`,
			'success' AS `message`,
			user_name,
			user_email,
			ifnull(user_location, '') AS user_location,
			CASE
			WHEN (user_last_login_at > now()-600) THEN 'Y'
			ELSE 'N' END AS `online`
			FROM tbl_users
			WHERE EXISTS
			(SELECT user_id
			FROM tbl_users
			WHERE user_token = ?)"$
			If id <> "all" Then
				strSQL = strSQL & " AND user_id = ?"
				' Check id is numeric?
				result = con.ExecQuery2(strSQL, Array As String(token, id))
			Else
				result = con.ExecQuery2(strSQL, Array As String(token))
			End If
		
			Dim List2 As List
			List2.Initialize
			Do While result.NextRow
				Dim Map2 As Map
				Map2.Initialize
				For i = 0 To result.ColumnCount - 1
					If result.GetColumnName(i) = "result" Then
						Map2.Put("result", result.GetInt("result"))
					Else
						Map2.Put(result.GetColumnName(i), result.GetString2(i))
					End If
				Next
				List2.Add(Map2)
			Loop
			Utility.ReturnJSON2(List2, Response)
		Else
			Utility.ReturnError("Error-Invalid-Token", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("user/view", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

' only update own profile, edit other users is restricted
Sub Update
	Dim con As SQL = pool.GetConnection
	Dim result As ResultSet
	Dim strSQL As String
	Dim msg_text As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("user/update", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
				
		Dim key As String = Map1.Get("key")
		Dim token As String = Map1.Get("token")
		Dim user_name As String = Map1.Get("user_name")
		Dim user_location As String = Map1.Get("user_location")
		If token = "" Or key = "" Then
			Utility.ReturnError("Error-Not-Authorized", Response)
			con.Close
			Return
		End If
		If user_name = "" Or user_location = "" Then
			msg_text = "[Not Set]"
			WriteUserLog("user/update", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		
		' Check Login session token
		strSQL = "SELECT user_id FROM tbl_users WHERE user_token = ?"
		result = con.ExecQuery2(strSQL, Array As String(token))
		If result.NextRow Then
			msg_text = "key: " & key
			strSQL = $"SELECT user_id AS result
			FROM tbl_users
			WHERE EXISTS (SELECT user_id FROM tbl_users WHERE user_api_key = ?)"$
			result = con.ExecQuery2(strSQL, Array As String(key))
			If result.NextRow Then
				strSQL = $"UPDATE tbl_users SET
				user_name = ?,
				user_location = ?,
				user_last_login_at = now(),
				modified_at = now()
				WHERE user_api_key = ?"$
				con.ExecNonQuery2(strSQL, Array As String(user_name, user_location, key))
			
				WriteUserLog("user/update", "success", msg_text, result.GetInt("result"))
				Utility.ReturnSuccess("success", Response)
			Else
				WriteUserLog("user/update", "fail", msg_text, 0)
				Utility.ReturnError("Error-No-Result", Response)
			End If
		Else
			Utility.ReturnError("Error-Invalid-Token", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("user/update", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub SendEmail(user_name As String, user_email As String, activation_code As String)
	Dim smtp As SMTP
	Try
		Dim settings As Map = Utility.ReadSettings
		Dim APP_TRADEMARK As String = settings.Get("APP_TRADEMARK")
		Dim SMTP_USERNAME As String = settings.Get("SMTP_USERNAME")
		Dim SMTP_PASSWORD As String = settings.Get("SMTP_PASSWORD")
		Dim SMTP_SERVER As String = settings.Get("SMTP_SERVER")
		Dim SMTP_USESSL As String = settings.Get("SMTP_USESSL")
		Dim SMTP_PORT As Int = settings.Get("SMTP_PORT")
		Dim ADMIN_EMAIL As String = settings.Get("ADMIN_EMAIL")

		smtp.Initialize(SMTP_SERVER, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, "SMTP")
		If SMTP_USESSL.ToUpperCase = "TRUE" Then smtp.UseSSL = True Else smtp.UseSSL = False
		smtp.HtmlBody = True
		LogDebug("Sending email...")
		smtp.Sender = SMTP_USERNAME
		smtp.To.Add(user_email)
		smtp.AuthMethod = smtp.AUTH_LOGIN
		smtp.subject = APP_TRADEMARK
		smtp.body = $"Hi ${user_name},<br />
		Please click on this link to finish the registration process:<br />
		<a href="${Main.ROOT_URL}/user/activate/${activation_code}" 
		id="activate-link" title="activate" target="_blank">${Main.ROOT_URL}/user/activate/${activation_code}</a><br />
		<br />
		If the link is not working, please copy the url to your browser.<br />
		<br />
		Regards,<br />
		<em>${APP_TRADEMARK}</em>"$	
		LogDebug(smtp.body)
		
		Dim sm As Object = smtp.Send
		Wait For (sm) SMTP_MessageSent (Success As Boolean)
		If Success Then
			LogDebug("Message sent successfully")
		Else
			LogDebug("Error sending message")
			LogDebug(LastException)
		End If
		
		'Notify site admin of new sign up
		smtp.Sender = SMTP_USERNAME
		smtp.To.Add(ADMIN_EMAIL)
		smtp.AuthMethod = smtp.AUTH_LOGIN
		smtp.HtmlBody = False
		smtp.subject = "New registration"
		smtp.body = $"Hi Admin,${CRLF}
		${user_name} has registered using our app."$
		
		Dim sm As Object = smtp.Send
		Wait For (sm) SMTP_MessageSent (Success As Boolean)
		If Success Then
			LogDebug("Message sent to Admin successfully")
		Else
			LogDebug("Error sending message to Admin")
			LogDebug(LastException)
		End If
	Catch
		LogDebug(LastException)
		Utility.ReturnError("Error-Send-Email", Response)
	End Try
End Sub

' =============================================================================
' https://www.mysqltutorial.org/mysql-triggers/working-mysql-scheduled-event/
' =============================================================================
' USE computer_api;
'
' CREATE EVENT clear_user_token_every_hour
' ON SCHEDULE EVERY 1 HOUR
' STARTS CURRENT_TIMESTAMP
' ENDS CURRENT_TIMESTAMP + INTERVAL 12 MONTH
' ON COMPLETION PRESERVE
' DO
'    Update tbl_users SET user_token = Null
'    WHERE user_last_login_at < NOW() - INTERVAL 1 HOUR;
' =============================================================================
' https://www.surekhatech.com/blog/mysql-event-scheduler
' =============================================================================
' SHOW PROCESSLIST;
' SET GLOBAL event_scheduler = ON;
' SHOW EVENTS FROM computer_api;
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
		Dim strView As String = Utility.ReadTextFile("password.html")
		strMain = Utility.BuildView(strMain, strView)
		strMain = Utility.BuildHtml(strMain, settings)
		Utility.ReturnHTML(strMain, Response)
		Return
	End If

	Dim ActionList As List
	ActionList.Initialize2(Array As String("change", "reset", "confirmreset"))
	If ActionList.IndexOf(elements(Main.ELEMENT_ACTION)) > -1 Then
		OpenConnection
	End If
	
	Select elements(Main.ELEMENT_ACTION)
		Case "change"
			ChangePassword
		Case "reset"
			ResetPassword
		Case "confirmreset"
			If elements.Length < Main.MAX_ELEMENTS Then Return
			ConfirmReset(elements(Main.ELEMENT_ID))
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
		LogDebug("[Password/RequestData] " & LastException)
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
		Dim strSQL As String = $"INSERT INTO tbl_error (error_text) SELECT ?"$
		con.ExecNonQuery2(strSQL, Array As String("[" & Module & "]" & Message))
	Catch
		LogDebug("[WriteErrorLog] " & LastException)
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

Sub ChangePassword
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("password/change", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		Dim user_email As String = Map1.Get("eml")
		Dim old_password As String = Map1.Get("old")
		Dim new_password As String = Map1.Get("new")
		
		If user_email = "" Or old_password = "" Or new_password = "" Then
			msg_text = "[Value Not Set]"
			WriteUserLog("password/change", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		
		If old_password = new_password Then
			msg_text = "[Same Password]"
			WriteUserLog("password/change", "fail", msg_text, 0)
			Utility.ReturnError("Error-Same-Value", Response)
			con.Close
			Return
		End If
		
		Dim strSQL As String
		strSQL = $"SELECT
		user_id AS `result`,
		'success' AS `message`,
		user_name,
		user_email,
		ifnull(user_location, '') AS user_location,
		ifnull(user_api_key, '') AS user_api_key,
		user_activation_flag
		FROM tbl_users
		WHERE user_email = ?
		AND user_hash = md5(concat(?, user_salt))"$

		Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(user_email, old_password))
		If result.NextRow Then
			Dim salt As String = Utility.MD5(Rnd(100001, 999999))
			Dim hash As String = Utility.MD5(new_password & salt)
			Dim key As String = Utility.SHA1(hash)

			' Update User Password
			strSQL = $"UPDATE tbl_users SET
			user_salt = ?,
			user_hash = ?,
			user_api_key = ?,
			user_token = NULL,
			modified_at = now()
			WHERE user_email = ?
			AND user_hash = MD5(concat(?, user_salt))"$
			con.ExecNonQuery2(strSQL, Array As String(salt, hash, key, user_email, old_password))

			WriteUserLog("password/change", "success", msg_text, result.GetInt("result"))
			Utility.ReturnSuccess("success", Response)
			
			' Send email
			SendEmail(result.GetString("user_name"), result.GetString("user_email"), "change", "null", "null")
		Else
			msg_text = "[Not Found] " & user_email
			WriteUserLog("password/change", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Result", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("password/change", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub ResetPassword
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Dim strSQL As String
	Try
		Dim Map1 As Map = RequestData
		If Map1 = Null Or Map1.IsInitialized = False Then
			msg_text = "[Null Value]"
			WriteUserLog("password/reset", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
		Dim user_email As String = Map1.Get("eml")
		
		If user_email = "" Then
			msg_text = "[Email Not Set]"
			WriteUserLog("password/reset", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Value", Response)
			con.Close
			Return
		End If
				
		strSQL = $"SELECT
		user_id AS `result`,
		'success' AS `message`,
		user_email,
		user_name
		FROM tbl_users
		WHERE user_email = ?"$
		Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(user_email))
		If result.NextRow Then
			Dim code As String = Utility.MD5(Rnd(100001, 999999))

			' Update User activation code
			strSQL = $"UPDATE tbl_users SET
			user_activation_code = ?,
			modified_at = now()
			WHERE user_email = ?"$
			con.ExecNonQuery2(strSQL, Array As String(code, user_email))
			
			WriteUserLog("password/reset", "success", msg_text, result.GetInt("result"))
			Utility.ReturnSuccess("success", Response)
			
			' Send email
			SendEmail(result.GetString("user_name"), result.GetString("user_email"), "reset", code, "null")		
		Else
			msg_text = "[Not Found] " & user_email
			WriteUserLog("password/reset", "fail", msg_text, 0)
			Utility.ReturnError("Error-No-Result", Response)
		End If
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("password/reset", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub ConfirmReset(code As String)
	Dim con As SQL = pool.GetConnection
	Dim msg_text As String
	Dim strMain As String
	Dim strSQL As String
	Try
		
		If code = "" Then
			strMain = $"<h1>Reset Password</h1>
			<p>Invalid reset code!</p>"$
			Utility.ReturnHTML(strMain, Response)
			con.Close
			Return
		Else			
			strSQL = $"SELECT
			user_name,
			user_email
			FROM tbl_users
			WHERE user_activation_code = ?"$
						
			Dim result As ResultSet = con.ExecQuery2(strSQL, Array As String(code))
			If result.NextRow Then
				' You may use other method To generate a more complex password with alphanumeric
				Dim salt As String = Utility.MD5(Rnd(100001, 999999))
				Dim temp As String = Utility.MD5(Rnd(100001, 999999))
				temp = temp.SubString(temp.Length - 8) ' get last 8 letters				
				Dim hash As String = Utility.MD5(temp & salt)
				Dim code As String = Utility.MD5(hash)
				
				strSQL = $"UPDATE tbl_users SET
				user_hash = ?,
				user_salt = ?,
				user_activation_code = ?,
				modified_at = now()
				WHERE user_email = ?"$
				con.ExecNonQuery2(strSQL, Array As String(hash, salt, code, result.GetString("user_email")))
				
				' Send email
				SendEmail(result.GetString("user_name"), result.GetString("user_email"), "confirmreset", "null", temp)			
			Else
				msg_text = "[Not Found] "
				WriteUserLog("password/confirmreset", "fail", msg_text, 0)
				strMain = $"<h1>Reset Password</h1>
				<p>Invalid reset code!</p>"$
				Utility.ReturnHTML(strMain, Response)
				con.Close
				Return
			End If
		End If		
	Catch
		msg_text = "[Exception] " & LastException
		WriteErrorLog("password/confirmreset", msg_text)
		Utility.ReturnError("Error-Execute-Query", Response)
	End Try
	If con <> Null And con.IsInitialized Then con.Close
End Sub

Sub SendEmail(user_name As String, user_email As String, action As String, reset_code As String, temp_password As String)
	Dim smtp As SMTP
	Dim strMain As String
	Try
		Dim settings As Map = Utility.ReadSettings
		Dim APP_TRADEMARK As String = settings.Get("APP_TRADEMARK")
		Dim SMTP_USERNAME As String = settings.Get("SMTP_USERNAME")
		Dim SMTP_PASSWORD As String = settings.Get("SMTP_PASSWORD")
		Dim SMTP_SERVER As String = settings.Get("SMTP_SERVER")
		Dim SMTP_USESSL As String = settings.Get("SMTP_USESSL")
		Dim SMTP_PORT As Int = settings.Get("SMTP_PORT")
		'Dim HTML_BODY As String = settings.Get("HTML_BODY")
		Dim EmailSubject As String
		Dim EmailBody As String
		
		Select Case action
			Case "change"
				EmailSubject = "Your password has been changed"
				EmailBody = $"Hi ${user_name},<br />
				We have noticed that you have changed your password recently.<br />
				<br />
				If this action is not initiated by you, please contact us immediately.<br />
				Otherwise, please ignore this email.<br />
				<br />
				Regards,<br />
				<em>${APP_TRADEMARK}</em>"$							
			Case "reset"
				EmailSubject = "Request to reset your password"
				EmailBody = $"Hi ${user_name},<br />
				We have received a request from you to reset your password.<br />
				<br />
				If this action is not initiated by you, please contact us immediately.<br />
				Otherwise, click the following link to confirm:<br />
				<br />
				<a href="${Main.ROOT_URL}/password/confirmreset/${reset_code}" id="reset-link" title="reset" target="_blank">${Main.ROOT_URL}/password/confirmreset/${reset_code}</a><br />
				<br />
				If the link is not working, please copy the url to your browser.<br />
				If you have changed your mind, just ignore this email.<br />				
				<br />
				Regards,<br />
				<em>${APP_TRADEMARK}</em>"$
			Case "confirmreset"
				EmailSubject = "Your password has been reset"
				EmailBody = $"Hi ${user_name},<br />
				Your password has been reset.<br />
				Please use the following temporary password to log in.<br />
				Password: ${temp_password}<br />
				<br />
				Once you are able to log in, please change to a new password.<br />
				<br />
				Regards,<br />
				<em>${APP_TRADEMARK}</em>"$
				
				strMain = $"<h1>Confirm Reset Password</h1>
				<p>Password reset successfully.<br/>Please check your email for temporary password.</p>"$
				Utility.ReturnHTML(strMain, Response)
			Case Else
				strMain = $"<h1>Send Email</h1>
				<p>Unrecognized action!</p>"$
				Utility.ReturnHTML(strMain, Response)
				Return
		End Select
		
		smtp.Initialize(SMTP_SERVER, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, "SMTP")
		If SMTP_USESSL.ToUpperCase = "TRUE" Then smtp.UseSSL = True Else smtp.UseSSL = False			
		smtp.Sender = SMTP_USERNAME
		smtp.To.Add(user_email)
		smtp.AuthMethod = smtp.AUTH_LOGIN
		'If HTML_BODY.ToUpperCase = "TRUE" Then smtp.HtmlBody = True Else smtp.HtmlBody = False
		smtp.HtmlBody = True
		smtp.Subject = EmailSubject
		smtp.Body = EmailBody
		LogDebug(smtp.body)
		LogDebug("Sending email...")
		'Dim sm As Object = smtp.Send
		Wait For (smtp.Send) SMTP_MessageSent (Success As Boolean)
		If Success Then
			LogDebug("Message sent successfully")
		Else
			LogDebug("Error sending message")
			LogDebug(LastException)
		End If
	Catch
		LogDebug(LastException)
		Utility.ReturnError("Error-Send-Email", Response)
	End Try
End Sub
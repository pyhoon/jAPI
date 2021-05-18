B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=4.19
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
	Select Request.RequestURI
		Case "/test/sendemail"			
			EmailTest
		Case "/test/connectdb"
			ConnectionTest
		Case "/test/readsettings"
			Dim settings As Map = Utility.ReadSettings
			LogDebug(settings.Get("SMTP_SERVER"))
			Response.Write("SMTP_SERVER: " & settings.Get("SMTP_SERVER"))
		Case Else
			Utility.ReturnSuccess("success", Response)
	End Select
End Sub

Sub ConnectionTest
	Try
		Dim config As Map = Utility.ReadConfig
		pool.Initialize(config.Get("DriverClass"), _
		config.Get("JdbcUrl"), _
		config.Get("User"), _
		config.Get("Password"))		
		
		' change pool size...
		' Credit to Harris
		' https://www.b4x.com/android/forum/threads/poolconnection-problem-connection-has-timed-out.95067/post-600974
		Dim jo As JavaObject = pool
		Dim MaxPoolSize As Int = config.Get("MaxPoolSize")
		jo.RunMethod("setMaxPoolSize", Array(MaxPoolSize))
		Dim con As SQL = pool.GetConnection
		If con <> Null And con.IsInitialized Then con.Close
		Response.Write("Connection successful.")
	Catch
		' If connection timeout, check database username and password are correct?
		LogDebug(LastException)
		Response.Write("Error fetching connection.")
	End Try
	If pool.IsInitialized Then pool.ClosePool
End Sub

' Send a test email to Admin Email
Sub EmailTest
	Try
		Dim SMTP As SMTP
		Dim settings As Map = Utility.ReadSettings
		Dim SMTP_USERNAME As String = settings.Get("SMTP_USERNAME")
		Dim SMTP_PASSWORD As String = settings.Get("SMTP_PASSWORD")
		Dim SMTP_SERVER As String = settings.Get("SMTP_SERVER")
		Dim SMTP_PORT As Int = settings.Get("SMTP_PORT")
		Dim SMTP_USESSL As String = settings.Get("SMTP_USESSL")
		Dim ADMIN_EMAIL As String = settings.Get("ADMIN_EMAIL")
		SMTP.Initialize(SMTP_SERVER, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, "SMTP")
		If SMTP_USESSL.ToUpperCase = "TRUE" Then SMTP.UseSSL = True Else SMTP.UseSSL = False
		'SMTP.StartTLSMode = True
		If ADMIN_EMAIL = "" Then
			LogDebug("SendEmail has been disabled!")
			Response.Write("Email test has been disabled!")
			Return
		End If
		Response.Write("EmailTest is running...")
		LogDebug("Sending email...")
		SMTP.Sender = SMTP_USERNAME
		SMTP.To.Add(ADMIN_EMAIL)
		SMTP.AuthMethod = SMTP.AUTH_LOGIN
		SMTP.HtmlBody = True
		SMTP.subject = "Message from B4J mail"
		SMTP.body = $"<strong>EMAIL TEST SUCCESS</strong>
		<hr>
		Email is sent from ${Main.ROOT_URL}<br/>
		The current time here is: ${DateTime.Time(DateTime.Now)}"$
		'SMTP.Send
		Wait For (SMTP.Send) SMTP_MessageSent (Success As Boolean)
		If Success Then
			LogDebug("Message sent successfully")
			Response.Write("Message sent successfully")
		Else
			' If failed, check values in settings.ini
			LogDebug("Error sending message")
			Response.Write("Error sending message")
		End If
	Catch
		LogDebug(LastException)
		Response.Write(LastException)
	End Try
End Sub
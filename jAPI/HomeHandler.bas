B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=8.1
@EndOfDesignText@
'Handler class
Sub Class_Globals

End Sub

Public Sub Initialize

End Sub

Sub Handle(req As ServletRequest, resp As ServletResponse)
	Dim settings As Map = Utility.ReadSettings
	settings.Put("ROOT_URL", Main.ROOT_URL)
	settings.Put("ROOT_PATH", Main.ROOT_PATH)
	Dim strMain As String = Utility.ReadTextFile("main.html")
	Dim strView As String = Utility.ReadTextFile("index.html")	
	strMain = Utility.BuildView(strMain, strView)
	strMain = Utility.BuildHtml(strMain, settings)
	Utility.ReturnHTML(strMain, resp)
End Sub
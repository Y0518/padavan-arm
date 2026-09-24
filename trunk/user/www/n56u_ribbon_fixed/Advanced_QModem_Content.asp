<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - 蜂窝模组</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">

<link rel="shortcut icon" href="images/favicon.ico">
<link rel="icon" href="images/favicon.png">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap.min.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/main.css">

<script type="text/javascript" src="/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script>
var $j = jQuery.noConflict();

<% login_state_hook(); %>

function initial(){
	show_banner(1);
	show_menu(5, 14, 1);
	show_footer();
}

function getResponse(){
	$j.get('/console_response.asp', function(data){
		var response = ($j.browser.msie && !is_ie11p) ? data.nl2br() : data;
		$j("#console_area").text(response);
		$j('#btn_exec').removeAttr('disabled');
	});
}

function qm(cmd){
	if (!login_safe())
		return false;
	$j('#btn_exec').attr('disabled', 'disabled');
	$j.post('/apply.cgi',
	{
		'action_mode': ' SystemCmd ',
		'current_page': 'console_response.asp',
		'next_page': 'console_response.asp',
		'SystemCmd': cmd
	},
	function(response){
		getResponse();
	});
}

function qm_at(){
	var c = $j('#at_cmd').val();
	if (c == "")
		return;
	qm("qmodem at " + c);
}
</script>
</head>

<body onLoad="initial();" >

<div class="wrapper">
    <div class="container-fluid" style="padding-right: 0px">
        <div class="row-fluid">
            <div class="span3"><center><div id="logo"></div></center></div>
            <div class="span9" >
                <div id="TopBanner"></div>
            </div>
        </div>
    </div>
    <div id="Loading" class="popup_bg"></div>
    <iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

    <form method="post" name="form" action="apply.cgi">
    <input type="hidden" name="current_page" value="">
    <input type="hidden" name="next_page" value="">
    <input type="hidden" name="next_host" value="">
    <input type="hidden" name="sid_list" value="">
    <input type="hidden" name="group_id" value="">
    <input type="hidden" name="action_mode" value="">
    <input type="hidden" name="action_script" value="">

    <div class="container-fluid">
        <div class="row-fluid">
            <div class="span3">
                <!--Sidebar content-->
                <div class="well sidebar-nav side_nav" style="padding: 0px;">
                    <ul id="mainMenu" class="clearfix"></ul>
                    <ul class="clearfix">
                        <li>
                            <div id="subMenu" class="accordion"></div>
                        </li>
                    </ul>
                </div>
            </div>

            <div class="span9">
                <!--Body content-->
                <div class="row-fluid">
                    <div class="span12">
                        <div class="box well grad_colour_dark_blue">
                            <h2 class="box_head round_top">蜂窝模组 (QModem)</h2>
                            <div class="round_bottom">
                                <div class="row-fluid">
                                    <div id="tabMenu" class="submenuBlock"></div>

                                    <table width="100%" cellpadding="4" cellspacing="0" class="table">
                                        <tr>
                                            <td style="border-top: 0 none">
                                                <button class="btn btn-primary" type="button" onclick="qm('qmodem scan');">扫描模组</button>
                                                <button class="btn btn-primary" type="button" onclick="qm('qmodem status');">状态查询</button>
                                                <button class="btn btn-warning" type="button" onclick="qm('qmodem dial');">启动拨号</button>
                                                <button class="btn" type="button" onclick="qm('qmodem stop');">停止拨号</button>
                                                <input type="text" id="at_cmd" class="input" style="width: 34%" placeholder="AT 命令，如 ATI"
                                                       onkeypress="if (event.keyCode === 13) qm_at();">
                                                <button class="btn" type="button" onclick="qm_at();">发送</button>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="border-top: 0 none">
                                                <span style="color: #888;">APN：<% nvram_get_x("", "qmodem_apn"); %>
                                                （设置：<code>nvram set qmodem_apn=你的APN &amp;&amp; nvram commit</code>，拨号前执行）</span>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="border-top: 0 none">
                                                <textarea class="span12" id="console_area" style="font-family: 'Courier New', Courier, mono; font-size:13px;" rows="20" wrap="off" readonly="1"></textarea>
                                            </td>
                                        </tr>
                                    </table>
                                </div>
                            </div>
                        </div>
                    </div>
                 </div>
            </div>
         </div>
    </div>
    </form>

     <div id="footer"></div>
</div>
</body>
</html>

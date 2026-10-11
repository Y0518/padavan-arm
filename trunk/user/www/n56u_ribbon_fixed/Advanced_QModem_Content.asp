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
	refresh_netinfo();
	qm_schedule();
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

/* ---- zx-qmodem: network information panel ------------------------------- */
var qm_timer = null;
var qm_auto = true;

function qm_kv_parse(txt){
	var o = {}, i, ls = String(txt).split('\n');
	for (i = 0; i < ls.length; i++){
		var p = ls[i].indexOf('=');
		if (p > 0)
			o[ls[i].substring(0, p).replace(/\r/g, '')] = ls[i].substring(p + 1).replace(/\r/g, '');
	}
	return o;
}

function qm_set(id, val){
	$j('#' + id).text((val === undefined || val === null || val === '') ? '-' : val);
}

function qm_fmt_bytes(v){
	var n = parseInt(v, 10), i = 0, u = ['B', 'KB', 'MB', 'GB', 'TB'];
	if (v === undefined || v === '' || isNaN(n))
		return '-';
	while (n >= 1024 && i < 4){ n = n / 1024; i++; }
	return (i === 0 ? n : n.toFixed(2)) + ' ' + u[i];
}

function qm_dial_badge(v){
	if (v == 'up')
		$j('#qm_dial').attr('class', 'label label-success').text('已连接');
	else
		$j('#qm_dial').attr('class', 'label').text('未连接');
}

function refresh_netinfo(){
	$j.get('/qmodem_netinfo.asp?_=' + (new Date()).getTime(), function(data){
		var d = qm_kv_parse(data);

		if (d.end != '1'){
			$j('#qm_state').attr('class', 'label label-important').text('采集未运行');
			$j('#qm_hint').text('点「开始采集」启动后台采集器（每 ' + (d.poll || 15) + ' 秒刷新一次）');
			$j('#qm_dial').attr('class', 'label').text('-');
			return;
		}

		if (d.monitor == 'on'){
			$j('#qm_state').attr('class', 'label label-success').text('采集中');
			$j('#qm_hint').text('每 ' + (d.poll || 15) + ' 秒刷新');
		} else {
			$j('#qm_state').attr('class', 'label label-warning').text('仅一次性');
			$j('#qm_hint').text('后台采集器未运行');
		}

		switch (d.state){
			case 'no_tool':
				$j('#qm_hint').text('固件里没有 sms_tool_q（编译未含 qmodem）');
				break;
			case 'no_modem':
				$j('#qm_hint').text('未检测到模组：请插入 USB 模组后点「扫描模组」');
				break;
			case 'no_sim':
				$j('#qm_hint').text('SIM 卡未就绪');
				break;
		}

		qm_set('qm_model', d.model);
		qm_set('qm_atport', d.at_port);
		qm_set('qm_sim', d.sim);
		qm_set('qm_operator', d.operator);
		qm_set('qm_netmode', d.netmode);
		qm_set('qm_reg', d.reg_text);
		qm_set('qm_cell', d.cell_raw);
		qm_set('qm_apn', d.apn ? d.apn : '(未设置)');
		qm_set('qm_dataif', d.data_if);
		qm_set('qm_ip4', d.ip4);
		qm_set('qm_rx', qm_fmt_bytes(d.rx_bytes));
		qm_set('qm_tx', qm_fmt_bytes(d.tx_bytes));
		qm_dial_badge(d.dial);

		if (d.signal_dbm !== undefined && d.signal_dbm !== ''){
			var pct = parseInt(d.signal_pct, 10);
			if (isNaN(pct)) pct = 0;
			qm_set('qm_signal', d.signal_dbm + ' dBm  (' + pct + '%)');
			$j('#qm_signal_bar').css('width', pct + '%');
			$j('#qm_signal_wrap').attr('class', 'progress' + (pct >= 60 ? ' progress-success' : (pct >= 25 ? ' progress-warning' : ' progress-danger')));
		} else {
			qm_set('qm_signal', '-');
			$j('#qm_signal_bar').css('width', '0%');
			$j('#qm_signal_wrap').attr('class', 'progress');
		}

		var t = parseInt(d.ts, 10);
		if (!isNaN(t))
			qm_set('qm_ts', (new Date(t * 1000)).toLocaleTimeString() + ' (' + Math.round(((new Date()).getTime() / 1000) - t) + ' 秒前)');

		$j('input[name=qm_auto]').attr('checked', qm_auto ? 'checked' : null);
	});
}

function qm_auto_toggle(){
	qm_auto = $j('input[name=qm_auto]').attr('checked') ? true : false;
	qm_schedule();
}

function qm_schedule(){
	if (qm_timer){ clearInterval(qm_timer); qm_timer = null; }
	if (qm_auto)
		qm_timer = setInterval(refresh_netinfo, 10000);
}

function qm_monitor(action){
	qm('qmodem monitor ' + action);
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

                                    <!-- zx-qmodem: 网络信息 -->
                                    <table width="100%" cellpadding="4" cellspacing="0" class="table table-bordered" style="margin-bottom:8px;">
                                        <tr>
                                            <td style="border-top:0 none; width:18%; color:#777;">运行状态</td>
                                            <td style="border-top:0 none; width:32%;">
                                                <span id="qm_state" class="label">-</span>
                                                <span id="qm_hint" style="color:#888; font-size:12px;"></span>
                                            </td>
                                            <td style="border-top:0 none; width:18%; color:#777;">更新时间</td>
                                            <td style="border-top:0 none; width:32%;"><span id="qm_ts">-</span></td>
                                        </tr>
                                        <tr>
                                            <td style="color:#777;">模组型号</td><td><span id="qm_model">-</span></td>
                                            <td style="color:#777;">AT 口</td><td><span id="qm_atport">-</span></td>
                                        </tr>
                                        <tr>
                                            <td style="color:#777;">SIM 卡</td><td><span id="qm_sim">-</span></td>
                                            <td style="color:#777;">注册状态</td><td><span id="qm_reg">-</span></td>
                                        </tr>
                                        <tr>
                                            <td style="color:#777;">信号强度</td>
                                            <td>
                                                <span id="qm_signal">-</span>
                                                <div id="qm_signal_wrap" class="progress" style="margin:4px 0 0 0; height:8px; width:80%;">
                                                    <div id="qm_signal_bar" class="bar" style="width:0%;"></div>
                                                </div>
                                            </td>
                                            <td style="color:#777;">网络制式</td><td><span id="qm_netmode">-</span></td>
                                        </tr>
                                        <tr>
                                            <td style="color:#777;">运营商</td><td><span id="qm_operator">-</span></td>
                                            <td style="color:#777;">服务小区</td>
                                            <td style="font-family:'Courier New',Courier,mono; font-size:12px; word-break:break-all;"><span id="qm_cell">-</span></td>
                                        </tr>
                                        <tr>
                                            <td style="color:#777;">APN</td><td><span id="qm_apn">-</span></td>
                                            <td style="color:#777;">拨号状态</td><td><span id="qm_dial" class="label">-</span></td>
                                        </tr>
                                        <tr>
                                            <td style="color:#777;">数据接口 / IP</td>
                                            <td><span id="qm_dataif">-</span> <span id="qm_ip4" style="font-family:'Courier New',Courier,mono;">-</span></td>
                                            <td style="color:#777;">流量 收 / 发</td>
                                            <td><span id="qm_rx">-</span> / <span id="qm_tx">-</span></td>
                                        </tr>
                                        <tr>
                                            <td style="border-bottom:0 none;" colspan="4">
                                                <button class="btn btn-small" type="button" onclick="refresh_netinfo();">刷新</button>
                                                <button class="btn btn-small" type="button" onclick="qm_monitor('start');">开始采集</button>
                                                <button class="btn btn-small" type="button" onclick="qm_monitor('stop');">停止采集</button>
                                                <label class="checkbox inline" style="margin-left:10px;">
                                                    <input type="checkbox" name="qm_auto" checked="checked" onclick="qm_auto_toggle();"> 自动刷新（10 秒）
                                                </label>
                                            </td>
                                        </tr>
                                    </table>

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

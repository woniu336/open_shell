/*
 *瀹濆闈㈡澘鍘婚櫎鍚勭璁＄畻棰樹笌寤舵椂绛夊緟
 *閫傜敤瀹濆闈㈡澘鐗堟湰锛�7.7
 *娑堝け鐨勫僵铏规捣
*/
if("undefined" != typeof bt && bt.hasOwnProperty("show_confirm")){
    bt.show_confirm = function(title, msg, callback, error) {
        layer.open({
            type: 1,
            title: title,
            area: "365px",
            closeBtn: 2,
            shadeClose: true,
            btn: [lan.public.ok, lan.public.cancel],
            content: "<div class='bt-form webDelete pd20'>\
					<p style='font-size:13px;word-break: break-all;margin-bottom: 5px;'>" + msg + "</p>" + (error || '') + "\
				</div>",
            yes: function (index, layero) {
                layer.close(index);
                if (callback) callback();
            }
        });
    }
}
if("undefined" != typeof bt && bt.hasOwnProperty("prompt_confirm")){
    bt.prompt_confirm = function (title, msg, callback) {
        layer.open({
            type: 1,
            title: title,
            area: "350px",
            closeBtn: 2,
            btn: ['纭', '鍙栨秷'],
            content: "<div class='bt-form promptDelete pd20'>\
            	<p>" + msg + "</p>\
            	</div>",
            yes: function (layers, index) {
                layer.close(layers)
                if (callback) callback()
            }
        });
    }
}
if("undefined" != typeof database && database.hasOwnProperty("del_database")){
    database.del_database = function (wid, dbname, callback) {
        var title = typeof dbname === "function" ?'鎵归噺鍒犻櫎鏁版嵁搴�':'鍒犻櫎鏁版嵁搴� [ '+ dbname +' ]';
        layer.open({
            type:1,
            title:title,
            icon:0,
            skin:'delete_site_layer',
            area: "530px",
            closeBtn: 2,
            shadeClose: true,
            content:"<div class=\'bt-form webDelete pd30\' id=\'site_delete_form\'>" +
                "<i class=\'layui-layer-ico layui-layer-ico0\'></i>" +
                "<div class=\'f13 check_title\' style=\'margin-bottom: 20px;\'>鏄惁纭銆愬垹闄ゆ暟鎹簱銆戯紝鍒犻櫎鍚庡彲鑳戒細褰卞搷涓氬姟浣跨敤锛�</div>" +
                "<div style=\'color:red;margin:18px 0 18px 18px;font-size:14px;font-weight: bold;\'>娉ㄦ剰锛氭暟鎹棤浠凤紝璇疯皑鎱庢搷浣滐紒锛侊紒"+(!recycle_bin_db_open?'<br>椋庨櫓鎿嶄綔锛氬綋鍓嶆暟鎹簱鍥炴敹绔欐湭寮€鍚紝鍒犻櫎鏁版嵁搴撳皢姘镐箙娑堝け锛�':'')+"</div>" +
                "</div>",
            btn:[lan.public.ok,lan.public.cancel],
            yes:function(indexs){
                var data = {id: wid,name: dbname};
                if(typeof dbname === "function"){
                    delete data.id;
                    delete data.name;
                }
                layer.close(indexs)
                if(typeof dbname === "function"){
                    dbname(data)
                }else{
                    bt.database.del_database(data, function (rdata) {
                        layer.closeAll()
                        if (rdata.status) database.database_table_view();
                        if (callback) callback(rdata);
                        bt.msg(rdata);
                    })
                }
            }
        })
    }
}
if("undefined" != typeof site && site.hasOwnProperty("del_site")){
    site.del_site = function(wid, wname, callback) {
        var title = typeof wname === "function" ?'鎵归噺鍒犻櫎绔欑偣':'鍒犻櫎绔欑偣 [ '+ wname +' ]';
        layer.open({
            type:1,
            title:title,
            icon:0,
            skin:'delete_site_layer',
            area: "440px",
            closeBtn: 2,
            shadeClose: true,
            content:"<div class=\'bt-form webDelete pd30\' id=\'site_delete_form\'>" +
                '<i class="layui-layer-ico layui-layer-ico0"></i>' +
                "<div class=\'f13 check_title\'>鏄惁瑕佸垹闄ゅ叧鑱旂殑FTP銆佹暟鎹簱銆佺珯鐐圭洰褰曪紒</div>" +
                "<div class=\"check_type_group\">" +
                "<label><input type=\"checkbox\" name=\"ftp\"><span>FTP</span></label>" +
                "<label><input type=\"checkbox\" name=\"database\"><span>鏁版嵁搴�</span>"+ (!recycle_bin_db_open?'<span class="glyphicon glyphicon-info-sign" style="color: red"></span>':'') +"</label>" +
                "<label><input type=\"checkbox\"  name=\"path\"><span>绔欑偣鐩綍</span>"+ (!recycle_bin_open?'<span class="glyphicon glyphicon-info-sign" style="color: red"></span>':'') +"</label>" +
                "</div>"+
                "</div>",
            btn:[lan.public.ok,lan.public.cancel],
            success:function(layers,indexs){
                $(layers).find('.check_type_group label').hover(function(){
                    var name = $(this).find('input').attr('name');
                    if(name === 'data' && !recycle_bin_db_open){
                        layer.tips('椋庨櫓鎿嶄綔锛氬綋鍓嶆暟鎹簱鍥炴敹绔欐湭寮€鍚紝鍒犻櫎鏁版嵁搴撳皢姘镐箙娑堝け锛�', this, {tips: [1, 'red'],time:0})
                    }else if(name === 'path' && !recycle_bin_open){
                        layer.tips('椋庨櫓鎿嶄綔锛氬綋鍓嶆枃浠跺洖鏀剁珯鏈紑鍚紝鍒犻櫎绔欑偣鐩綍灏嗘案涔呮秷澶憋紒', this, {tips: [1, 'red'],time:0})
                    }
                },function(){
                    layer.closeAll('tips');
                })
            },
            yes:function(indexs){
                var data = {id: wid,webname: wname};
                $('#site_delete_form input[type=checkbox]').each(function (index, item) {
                    if($(item).is(':checked')) data[$(item).attr('name')] = 1
                })
                var is_database = data.hasOwnProperty('database'),is_path = data.hasOwnProperty('path'),is_ftp = data.hasOwnProperty('ftp');
                if((!is_database && !is_path) && (!is_ftp || is_ftp)){
                    if(typeof wname === "function"){
                        wname(data)
                        return false;
                    }
                    bt.site.del_site(data, function (rdata) {
                        layer.close(indexs);
                        if (callback) callback(rdata);
                        bt.msg(rdata);
                    })
                    return false
                }
                if(typeof wname === "function"){
                    delete data.id;
                    delete data.webname;
                }
                layer.close(indexs)
                if(typeof wname === "function"){
                    console.log(data)
                    wname(data)
                }else{
                    bt.site.del_site(data, function (rdata) {
                        layer.closeAll()
                        if (rdata.status) site.get_list();
                        if (callback) callback(rdata);
                        bt.msg(rdata);
                    })
                }
            }
        })
    }
}
if("undefined" != typeof bt && bt.hasOwnProperty("firewall") && bt.firewall.hasOwnProperty("add_accept_port")){
    bt.firewall.add_accept_port = function(type, port, ps, callback) {
        var action = "AddDropAddress";
        if (type == 'port') {
            ports = port.split(':');
            if (port.indexOf('-') != -1) ports = port.split('-');
            for (var i = 0; i < ports.length; i++) {
                if (!bt.check_port(ports[i])) {
                    layer.msg(lan.firewall.port_err, { icon: 5 });
                    return;
                }
            }
            action = "AddAcceptPort";
        }

        loading = bt.load();
        bt.send(action, 'firewall/' + action, { port: port, type: type, ps: ps }, function(rdata) {
            loading.close();
            if (callback) callback(rdata);
        })
    }
}
if("undefined" != typeof bt && bt.hasOwnProperty("system") && bt.system.hasOwnProperty("check_update")){
    bt.system.check_update = function(callback, check) {
        var rdata = {status:false, msg:{beta:{},adviser:-1,btb:'',downUrl:'',force:false,is_beta:0,updateMsg:'',uptime:'',version:'7.7.0'}};
        if (check) load.close();
        if (callback) callback(rdata);
    }
}
function SafeMessage(j, h, g, f) {
	if(f == undefined) {
		f = ""
	}
	var mess = layer.open({
		type: 1,
		title: j,
		area: "350px",
		closeBtn: 2,
		shadeClose: true,
		content: "<div class='bt-form webDelete pd20 pb70'><p>" + h + "</p>" + f + "<div class='bt-form-submit-btn'><button type='button' class='btn btn-danger btn-sm bt-cancel'>"+lan.public.cancel+"</button> <button type='button' id='toSubmit' class='btn btn-success btn-sm' >"+lan.public.ok+"</button></div></div>"
	});
	$(".bt-cancel").click(function(){
		layer.close(mess);
	});
	$("#toSubmit").click(function() {
		layer.close(mess);
		g();
	})
}
$(document).ready(function () {
    if($('#updata_pro_info').length>0){
        $('#updata_pro_info').html('');
        bt.set_cookie('productPurchase', 1);
    }
})
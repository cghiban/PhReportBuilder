function browse(path) {
	var w = window.open(path, 'fsbrowser', 'height=400,width=600,resizable=no,scrollbars=yes,location=no');
	if (window.focus) {w.focus();}
}

function goPath(path) {
   window.location.href = path + window.location.hash;
}

function selectDir(dir) {
	var o = window.opener;
	if (o) {
		o.document.getElementById('d').value = dir;
		window.close();
	}
}

function selectFile(file) {
	var o = window.opener;
	if (o) {
		o.document.getElementById('r').value = file;
		window.close();
	}
}

function doBuild() {
	var out=document.getElementById('o');
	out.value = out.value.replace(/\s+$/g, '');
	out.value = out.value.replace(/^\s+/g, '');
	//if (/['"\\\/.\s]/.test(out.value)) {
	if (/[\W]/.test(out.value)) {
		alert("Output must contain only letters and digits!");
		out.focus();
		return;
	}
	
	document.getElementById('build_btn').style.display='none';
	var f=document.getElementById('forma1');
	document.getElementById('aha').src='about:blank';
	f.submit();
}

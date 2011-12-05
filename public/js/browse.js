function browse(path) {
	var w = window.open(path, 'fsbrowser', 'height=400,width=600,resizable=no,scrollbars=yes,location=no');
	if (window.focus) {w.focus();}
}

function goPath(path) {
   window.location.href = path + window.location.hash;
}

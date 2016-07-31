module liara.nodes.formatting;

import liara;
import std.conv;
import std.xml;


package string processNode_Bold(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<strong>` ~ parseAll!true(p.children) ~ `</strong>`
		: parseAll!false(p.children);
}


package string processNode_Italic(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<em>` ~ parseAll!true(p.children) ~ `</em>`
		: parseAll!false(p.children);
}


package string processNode_Del(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<del>` ~ parseAll!true(p.children) ~ `</del>`
		: parseAll!false(p.children);
}


package string processNode_Code(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<code>` ~ parseAll!true(p.children) ~ `</code>`
		: parseAll!false(p.children);
}


package string processNode_QuotationMark(bool htmlMode)(ParseTree p) {
	return htmlMode ? "" : p.input[p.begin..p.end];
}


package string processNode_Ruler(bool htmlMode)(ParseTree p) {
	return htmlMode ? "<hr/>\n\n" : p.input[p.begin..p.end]~"\n\n";
}


package string processNode_NewLine(bool htmlMode)(ParseTree p) {
	return htmlMode ? "<br/>\n" : "\n";
}


package string processNode_Heading(bool htmlMode)(ParseTree p) {
	if (!htmlMode) {
		return p.matches[$-1]~"\n\n";
	}
	else {
		ulong level = 7 - p.matches[0].length;
		string tag = "h" ~ level.to!string;
		
		if (p.matches.length > 2)
			return `<`~tag~`><a name="`~encode(p.matches[1])~`"></a> `~encode(p.matches[2])~`</`~tag~">\n\n";
		else
			return `<`~tag~`>`~encode(p.matches[1])~"</"~tag~">\n\n";
	}
}


package string processNode_Pre(bool htmlMode)(ParseTree p) {
	immutable string language = p.matches.length>1 ? p.matches[0] : null;
	immutable string source = p.matches[$-1];
	
	if (!htmlMode)
		return source~"\n\n";
	else if (language)
		return "<pre data-language=\""~language~"\">\n"~encode(source)~"\n</pre>\n\n";
	else
		return "<pre>\n"~encode(source)~"\n</pre>\n\n";
}
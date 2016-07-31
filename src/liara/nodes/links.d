module liara.nodes.links;

import liara;
import liara.params;
import pegged.grammar;
import std.xml;


package string processNode_AutoUrl(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<a href="`~encode(p.matches[0])~`">`~encode(p.matches[0])~`</a>`
		: p.matches[0];
}


package string processNode_Link(bool htmlMode)(ParseTree p) {
	// A link to any target, either local or global, with an optional label.
	// It is up to user-defined code to convert given target string to valid URL.
	// Sometimes user-defined code can also generate label for given target.
	
	bool needLabel = (p.matches.length == 1);
	if (!htmlMode && !needLabel) {
		// When we have no need to get URL and we have title, just show the title
		return parseAll!false(p.children);
	}
	else {
		Link link = parserParams.makeLink(p.matches[0], needLabel);
		if (!htmlMode) {
			return link.label;
		}
		else {
			string label = needLabel ? encode(link.href) : parseAll!true(p.children);
			return `<a`
				~ (link.cssClass ? ` class="`~link.cssClass~`"` : "")
				~ ` href="`~encode(link.href)~`">`
				~ label
			~ `</a>`;
		}
	}
}
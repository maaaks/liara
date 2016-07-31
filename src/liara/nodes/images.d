module liara.nodes.images;

import liara;
import pegged.grammar;
import std.algorithm.iteration;
import std.array;
import std.regex;
import std.xml;


// Block image ("!image.png" or "!!image.png") is rendered as <p><img/></p>.
package string processNode_BlockImage(bool htmlMode)(ParseTree p) {
	if (!htmlMode) {
		return "";
	}
	else {
		string attributes;             /// The attributes for <img>
		string[] pClasses = ["image"]; /// List of classes to be used for <p> around the <img>
		string link;                   /// Will be set to the image's link target
		
		// Use custom function to process the image URL
		string src = parserParams.processImageUrl(p.matches[1]);
		
		// By default, set "alt" attribute to the image name
		string alt = src.split("/")[$-1];
		
		// Now process optional arguments, one by one
		for (auto i=1; i<p.children.length; i++) {
			ParseTree c = p.children[i];
			final switch (c.name)
			{
				case "Liara.ImgAlt":
					alt = c.matches[0];
					break;
				
				case "Liara.ImgSize":
					attributes ~= " width=\""~c.matches[0]~"\" height=\""~c.matches[1]~"\"";
					break;
				
				case "Liara.ImgLink":
					link = c.matches[0];
					break;
				
				case "Liara.ImgCenter": pClasses ~= "center"; break;
				case "Liara.ImgLeft":   pClasses ~= "left";   break;
				case "Liara.ImgRight":  pClasses ~= "right";  break;
			}
		}
		
		// Now render <img>...
		string result = "<img alt=\""~encode(alt)~"\" src=\""~encode(src)~"\""~attributes~"/>";
		
		// ...wrap it in <a> if necessary...
		if (link)
			result = "<a href=\""~encode(link)~"\">"~result~"</a>";
		
		// ...wrap it in <p class="image"> (optionally with some additional classes) and return.
		return "<p class=\""~uniq(pClasses).join(" ")~"\">"~result~"</p>\n\n";
	}
}
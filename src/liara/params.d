module liara.params;

import liara;
import std.xml;

/// Simple class representing a HTML link.
class Link
{
	string href;
	string label;
	string cssClass;
	
	this(in string href, in string label, in string cssClass=null) {
		this.href = href;
		this.label = label;
		this.cssClass = cssClass;
	}
}


/// Parameters for the parser.
class LiaraParams
{
	bool makeHtml     = true;  /// If true, parser will generate HTML output.
	bool makePlain    = false; /// If true, parser will generate plain text output.
	bool addClassLast = true;  /// If true, adds class="last" to the last paragraph in HTML mode.
	
	/**
		Function for creating a Link object.
		Called when Liara finds something like "((http://example.org some label))".
		
		First argument is target which user entered (for example, a URL).
		Sometimes you may want to modify it, e.g. to convert local links to global,
		but in the simplest case you just assign it to the «href» field of returning object.
		
		Second argument indicates whether you should generate label for it or not.
		If it is true, Liara assumes that the resulting Link object will contain
		a label formmed by you, e.g. auto-detected title of a linked article.
		If it is false, you do not have to waste your time for forming the label
		because Liara will override it with the text that user entered anyway.
	 */
	abstract Link makeLink(string target, bool needLabel);
	
	/**
		Function for converting non-absolute image paths to full URLs.
		Called when Liara finds image paths that are not full HTTPS URLs, e.g. "image.png".
		
		For example, your code can implement access to local files of the text's author
		by their short names.
	 */
	abstract string processImageUrl(string url);
	
	/**
		Function for creating custom blocks.
		Called when Liara finds one-line paragraphs like "&video https://vimeo.com/59230893".
		
		The plugin name (e.g. "video") is passed as first argument, while the rest of the line,
		without leading and trailing spaces, is passed as second argument.
		The function should construct and return HTML code for the block,
		including the wrapping <p> tag if needed.
		
		When the block is the whole text's last block, addLast argument will be set to true.
		It can be used to add some special CSS classes to such blocks.
	 */
	abstract string makeBlock(string pluginName, string input, bool addLast);
}

/**
	Exception to be thrown when an unknown plugin name is used.
 */
class UnsupportedPluginException: Exception
{
	immutable string pluginName;
	
	this(in string pluginName) {
		this.pluginName = pluginName;
		super("Unsupported plugin: "~pluginName);
	}
}
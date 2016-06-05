import core.exception;
import core.stdc.stdlib;
import liara.params;
import liara.parser;
import pegged.grammar;
import std.array;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;


class TestParams: LiaraParams
{
	this() {
		this.addClassLast = false;
	}
	
	override Link makeLink(string target, bool needLabel) {
		string label = target.match(ctRegex!`^https?://`) ? target : "Click here";
		return new Link(target, label);
	}
	
	override string makeBlock(string pluginName, string input, bool addLast, LiaraResult* r) {
		return "[["~pluginName~"]]";
	}
	
	override string processImageUrl(string url) {
		return url.match(ctRegex!`^https?://`) ? url : "https://example.org/"~url;
	}
}


private void assertText(bool singleLineMode=false)(string rawTestInput,
string testHtmlOutput, string testPlainOutput=null, OpeningType expectedOpeningType=OpeningType.Undefined) {
	foreach (testInput; [rawTestInput, rawTestInput.replace("\n", "\r\n"), rawTestInput.replace("\n", "\r")]) {
		// When testPlainOutput not given, that means nothing should be changed in the text
		if (!testPlainOutput)
			testPlainOutput = testInput;
		
		// Run the parser
		auto result = parseLiara!LiaraResultExtended(testInput, new TestParams);
		string htmlOutput = result.htmlOutput;
		string plainOutput = result.plainOutput;
		
		// In single line mode, cut off "<p>" and "</p>\n\n" for HTML mode and "\n\n" for plain text mode
		static if (singleLineMode) {
			htmlOutput = htmlOutput[3..$-6];
			plainOutput = plainOutput[0..$-2];
		}
		
		// Make strings more print-friendly
		testInput       =       testInput.strip().replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n");
		htmlOutput      =      htmlOutput.strip().replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n");
		plainOutput     =     plainOutput.strip().replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n");
		testHtmlOutput  =  testHtmlOutput.strip().replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n");
		testPlainOutput = testPlainOutput.strip().replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n");
		
		// Now check if the results are correct
		try { assert(htmlOutput == testHtmlOutput); }
		catch(AssertError e) {
			writeln("[FAIL] "~testInput);
			writeln(result.tree);
			writeln("      SOURCE: "~testInput.replace("\n","\\n"));
			writeln("        HTML: "~htmlOutput);
			writeln(" WANTED HTML: "~testHtmlOutput);
			exit(0);
		}
		
		try { assert(plainOutput == testPlainOutput); }
		catch(AssertError e) {
			writeln("[FAIL] "~testInput);
			writeln(result.tree);
			writeln("      SOURCE: "~testInput.replace("\n","\\n"));
			writeln("       PLAIN: "~plainOutput);
			writeln("WANTED PLAIN: "~testPlainOutput);
			exit(0);
		}
		
		try { assert(expectedOpeningType == OpeningType.Undefined || expectedOpeningType == result.openingType); }
		catch(AssertError e) {
			writeln("[FAIL] "~testInput);
			writeln(result.tree);
			writeln("      SOURCE: "~testInput.replace("\n","\\n"));
			writeln("       OTYPE:", result.openingType);
			writeln("WANTED OTYPE:", expectedOpeningType);
		}
	}
	
	version(unittest) writeln("[ OK ] "~rawTestInput.replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n"));
}

/// Shorthand for checking single lines, without paragraphs.
alias assertText!true assertLine;


unittest {
	// Basic formatting
	assertLine(`Here is **some bold text**.`,         `Here is <strong>some bold text</strong>.`,                `Here is some bold text.`);
	assertLine(`Here is __some italic text__.`,       `Here is <em>some italic text</em>.`,                      `Here is some italic text.`);
	assertLine(`Here is ~~some deleted text~~.`,      `Here is <del>some deleted text</del>.`,                   `Here is some deleted text.`);
	assertLine("Here is `some code`.",                `Here is <code>some code</code>.`,                         `Here is some code.`);
	assertLine(`__Here is **bold** inside italic.__`, `<em>Here is <strong>bold</strong> inside italic.</em>`,   `Here is bold inside italic.`);
	assertLine(`**Here is __italic__ inside bold.**`, `<strong>Here is <em>italic</em> inside bold.</strong>`,   `Here is italic inside bold.`);
	assertLine("`Here is **bold** inside code.`",     `<code>Here is <strong>bold</strong> inside code.</code>`, `Here is bold inside code.`);
	assertLine(`Formatting p**art**s of w__ord__s.`,  `Formatting p<strong>art</strong>s of w<em>ord</em>s.`,    `Formatting parts of words.`);
	assertLine(`Formatt**ing part**s o__f word__s.`,  `Formatt<strong>ing part</strong>s o<em>f word</em>s.`,    `Formatting parts of words.`);
	// HTML
	assertLine(`__HTML <b>doesn't work</b> here.__`, `<em>HTML &lt;b&gt;doesn&apos;t work&lt;/b&gt; here.</em>`, `HTML <b>doesn't work</b> here.`);
	assertLine(`<b>"HTML"</b> doesn't <em>work</em>.`, `&lt;b&gt;&quot;HTML&quot;&lt;/b&gt; doesn&apos;t &lt;em&gt;work&lt;/em&gt;.`);
	
	// Plain urls
	assertLine(`https://ongra.net/`,                  `<a href="https://ongra.net/">https://ongra.net/</a>`);
	assertLine(`Welcome to https://ongra.net/.`,      `Welcome to <a href="https://ongra.net/">https://ongra.net/</a>.`);
	assertLine(`Welcome to https://ongra.net/!`,      `Welcome to <a href="https://ongra.net/">https://ongra.net/</a>!`);
	assertLine(`Welcome to https://ongra.net/! Hi!`,  `Welcome to <a href="https://ongra.net/">https://ongra.net/</a>! Hi!`);
	assertLine(`Visit https://ongra.net, it's cool!`, `Visit <a href="https://ongra.net">https://ongra.net</a>, it&apos;s cool!`);
	assertLine(`Ongra (https://ongra.net/) is cool.`, `Ongra (<a href="https://ongra.net/">https://ongra.net/</a>) is cool.`);
	
	// Links
	assertLine(`Simple link: ((https://maaaks.ru/)).`, `Simple link: <a href="https://maaaks.ru/">https://maaaks.ru/</a>.`,      `Simple link: https://maaaks.ru/.`);
	assertLine(`Labeled link: ((https://maaaks.ru/ custom label)).`, `Labeled link: <a href="https://maaaks.ru/">custom label</a>.`, `Labeled link: custom label.`);
	assertLine(`((https://maaaks.ru/ **Formatting** inside link)).`,
		`<a href="https://maaaks.ru/"><strong>Formatting</strong> inside link</a>.`, `Formatting inside link.`);
	assertLine(`**((https://maaaks.ru/ Link)) inside formatting.**`,
		`<strong><a href="https://maaaks.ru/">Link</a> inside formatting.</strong>`, `Link inside formatting.`);
	// HTML
	assertLine(`((https://<b>maaaks.ru</b>/))`,
		`<a href="https://&lt;b&gt;maaaks.ru&lt;/b&gt;/">https://&lt;b&gt;maaaks.ru&lt;/b&gt;/</a>`, `https://<b>maaaks.ru</b>/`);
	assertLine(`((https://<b>maaaks.ru</b>/ <i>click here</i>))`,
		`<a href="https://&lt;b&gt;maaaks.ru&lt;/b&gt;/">&lt;i&gt;click here&lt;/i&gt;</a>`,         `<i>click here</i>`);
	
	// Rulers
	assertText(`---`,     `<p>---</p>`);
	assertText(`----`,    `<hr/>`);
	assertText(`-------`, `<hr/>`);
	assertText(`===`,     `<p>===</p>`);
	assertText(`====`,    `<hr/>`);
	assertText(`=======`, `<hr/>`);
	
	// Paragraphs
	assertText("First\nparagraph.\n\nSecond paragraph.", "<p>First<br/>\nparagraph.</p>\n\n<p>Second paragraph.</p>");
	assertText("Paragraph.\n\n====\n\nParagraph.", "<p>Paragraph.</p>\n\n<hr/>\n\n<p>Paragraph.</p>");
	assertText("Multiple newlines are collapsed.\n\n\n\n\nOk.",
		"<p>Multiple newlines are collapsed.</p>\n\n<p>Ok.</p>", "Multiple newlines are collapsed.\n\nOk.");
	
	// Headings
	assertText(":::: Heading 3\n\nText", "<h3>Heading 3</h3>\n\n<p>Text</p>\n\n", "Heading 3\n\nText");
	assertText(":::  Heading 4\n\nText", "<h4>Heading 4</h4>\n\n<p>Text</p>\n\n", "Heading 4\n\nText");
	assertText("::   Heading 5\n\nText", "<h5>Heading 5</h5>\n\n<p>Text</p>\n\n", "Heading 5\n\nText");
	assertText(":    Heading 6\n\nText", "<h6>Heading 6</h6>\n\n<p>Text</p>\n\n", "Heading 6\n\nText");
	assertText("::::(anchor) Heading 3\n\nText", "<h3><a name=\"anchor\"></a> Heading 3</h3>\n\n<p>Text</p>\n\n", "Heading 3\n\nText");
	assertText(":::(anchor)  Heading 4\n\nText", "<h4><a name=\"anchor\"></a> Heading 4</h4>\n\n<p>Text</p>\n\n", "Heading 4\n\nText");
	assertText("::(anchor)   Heading 5\n\nText", "<h5><a name=\"anchor\"></a> Heading 5</h5>\n\n<p>Text</p>\n\n", "Heading 5\n\nText");
	assertText(":(anchor)    Heading 6\n\nText", "<h6><a name=\"anchor\"></a> Heading 6</h6>\n\n<p>Text</p>\n\n", "Heading 6\n\nText");
	// HTML
	assertText(":::: <b>HTML</b> rules!\n\nText",
		"<h3>&lt;b&gt;HTML&lt;/b&gt; rules!</h3>\n\n<p>Text</p>\n\n",                                          "<b>HTML</b> rules!\n\nText");
	assertText("::::(<i>hehe</i>) <b>HTML</b> rules!\n\nText",
		"<h3><a name=\"&lt;i&gt;hehe&lt;/i&gt;\"></a> &lt;b&gt;HTML&lt;/b&gt; rules!</h3>\n\n<p>Text</p>\n\n", "<b>HTML</b> rules!\n\nText");
	
	// Blockquotes
	assertText("One.\n\n> Two.\n\nThree.",
		"<p>One.</p>\n\n<blockquote>\n\n<p>Two.</p>\n\n</blockquote>\n\n<p>Three.</p>\n\n");
	assertText("One.\n\n> Two.\n\n> > Three.",
		"<p>One.</p>\n\n<blockquote>\n\n<p>Two.</p>\n\n<blockquote>\n\n<p>Three.</p>\n\n</blockquote>\n\n</blockquote>");
	assertText("> One.\n\n> > Two.\n\n> Three.",
		"<blockquote>\n\n<p>One.</p>\n\n<blockquote>\n\n<p>Two.</p>\n\n</blockquote>\n\n<p>Three.</p>\n\n</blockquote>");
	
	// Block cuts
	assertText("(((CUT)))\n\nThis was a cut.\n\n(((/CUT)))",
		"<div class=\"cut\">Читать дальше »</div>\n<div class=\"undercut\">\n\n<p>This was a cut.</p>\n\n</div>",
		"This was a cut.");
	assertText("(((CUT:Read them all!)))\n\nThis was a labeled cut.\n\n(((/CUT)))",
		"<div class=\"cut\">Read them all!</div>\n<div class=\"undercut\">\n\n<p>This was a labeled cut.</p>\n\n</div>",
		"This was a labeled cut.");
	assertText("(((CUT)))\n\nMultiple\n\nparagraphs\n\ninside\n\nsingle cut.\n\n(((/CUT)))",
		"<div class=\"cut\">Читать дальше »</div>\n<div class=\"undercut\">\n\n<p>Multiple</p>\n\n<p>paragraphs</p>\n\n<p>inside</p>\n\n<p>single cut.</p>\n\n</div>",
		"Multiple\n\nparagraphs\n\ninside\n\nsingle cut.");
	assertText("An abandoned block closing tag:\n\n(((/CUT)))",
		"<p>An abandoned block closing tag:</p>",
		"An abandoned block closing tag:");
	assertText("(((CUT)))\n\nA working block cut.\n\n(((/CUT)))\n\nAn abandoned block closing tag:\n\n(((/CUT)))",
		"<div class=\"cut\">Читать дальше »</div>\n<div class=\"undercut\">\n\n<p>A working block cut.</p>\n\n</div>\n\n<p>An abandoned block closing tag:</p>",
		"A working block cut.\n\nAn abandoned block closing tag:");
	// HTML
	assertText("(((CUT:<b>Read</b>!)))\n\nLabeled cut.\n\n(((/CUT)))",
		"<div class=\"cut\">&lt;b&gt;Read&lt;/b&gt;!</div>\n<div class=\"undercut\">\n\n<p>Labeled cut.</p>\n\n</div>",
		"Labeled cut.");
	
	// Inline cuts
	assertLine(`This is (((CUT)))inline cut!(((/CUT)))`,
		`This is <span class="cut">Читать дальше »</span><span class="undercut">inline cut!</span>`,
		"This is inline cut!");
	assertLine(`This is (((CUT:what?)))labeled inline cut!(((/CUT)))`,
		`This is <span class="cut">what?</span><span class="undercut">labeled inline cut!</span>`,
		"This is labeled inline cut!");
	assertLine("An abandoned inline closing tag: (((/CUT))).",
		"An abandoned inline closing tag: .",
		"An abandoned inline closing tag: .");
	assertLine("A (((CUT)))working inline cut(((/CUT))) and then an abandoned inline closing tag: (((/CUT))).",
		"A <span class=\"cut\">Читать дальше »</span><span class=\"undercut\">working inline cut</span> and then an abandoned inline closing tag: .",
		"A working inline cut and then an abandoned inline closing tag: .");
	// HTML
	assertLine(`This is (((CUT:<b>what</b>?)))labeled inline cut!(((/CUT)))`,
		`This is <span class="cut">&lt;b&gt;what&lt;/b&gt;?</span><span class="undercut">labeled inline cut!</span>`,
		"This is labeled inline cut!");
	
	// Empty cuts
	assertLine("This inline cut (((CUT)))(((/CUT))) shouldn't be shown.",
		"This inline cut  shouldn&apos;t be shown.",
		"This inline cut  shouldn't be shown.");
	assertText("This block cut...\n\n(((CUT)))\n\n(((/CUT)))\n\n...shouldn't be shown, too.",
		"<p>This block cut...</p>\n\n<p>...shouldn&apos;t be shown, too.</p>",
		"This block cut...\n\n...shouldn't be shown, too.");
	
	// Combined cuts
	assertText("Combined 1. Before the cut. (((CUT:Read more)))Begin cut.\n\nContinue cut.\n\nEnd cut.(((/CUT))) After the cut.",
		"<p>Combined 1. Before the cut. <span class=\"cut\">Read more</span><span class=\"undercut\">Begin cut.</span></p>\n\n"
		"<div class=\"undercut\">\n\n<p>Continue cut.</p>\n\n</div>\n\n"
		"<p><span class=\"undercut\">End cut.</span> After the cut.</p>",
		"Combined 1. Before the cut. Begin cut.\n\nContinue cut.\n\nEnd cut. After the cut.");
	//assertText("(((CUT:Combined 2.)))\n\nWritten as block cut, but actually an inline cut.(((/CUT))) After the cut.",
	//	"<p><span class=\"cut\">Combined 2.</span>"
	//	"<span class=\"undercut\">Written as block cut, but actually an inline cut.</span> After the cut.</p>");
	//assertText("(((CUT:Combined 3.)))Written as inline cut, but actually a block cut.(((/CUT)))",
	//	"<div class=\"cut\">Combined 3.</div>\n<div class=\"undercut\">\n\n"
	//	"<p>Written as inline cut, but actually a block cut.</p>\n\n</div");
	
	// Code blocks
	assertText("Text.\n\n```\nSome code.\n```\n\nText.",
		"<p>Text.</p>\n\n<pre>\nSome code.\n</pre>\n\n<p>Text.</p>\n\n",
		"Text.\n\nSome code.\n\nText.");
	assertText("Text.\n\n```c++\nSome code.\n```\n\nText.",
		"<p>Text.</p>\n\n<pre data-language=\"c++\">\nSome code.\n</pre>\n\n<p>Text.</p>\n\n",
		"Text.\n\nSome code.\n\nText.");
	
	// Block images
	assertText("Before.\n\n!image.png\n\nAfter.",
		"<p>Before.</p>\n\n<p class=\"blockimage\"><img alt=\"image.png\" src=\"https://example.org/image.png\"/></p>\n\n<p>After.</p>",
		"Before.\n\nAfter.");
	assertText(`!image.png`, `<p class="blockimage"><img alt="image.png" src="https://example.org/image.png"/></p>`,                                        "");
	assertText(`!image.png -alt "Some alt text"`, `<p class="blockimage"><img alt="Some alt text" src="https://example.org/image.png"/></p>`,               "");
	assertText(`!image.png -size 640x480`, `<p class="blockimage"><img alt="image.png" src="https://example.org/image.png" width="640" height="480"/></p>`, "");
	assertText(`!!image.png`, `<p class="blockimage wide"><img alt="image.png" src="https://example.org/image.png"/></p>`,                                  "");
	assertText(`!image.png -dark`, `<p class="blockimage"><img alt="image.png" src="https://example.org/image.png"/></p>`,                                  "");
	assertText(`!!image.png -dark`, `<p class="blockimage wide"><img alt="image.png" src="https://example.org/image.png"/></p>`,                           "");
	assertText(`!image.png -center`, `<p class="blockimage center"><img alt="image.png" src="https://example.org/image.png"/></p>`,                        "");
	assertText(`!image.png -left`, `<p class="blockimage left"><img alt="image.png" src="https://example.org/image.png"/></p>`,                             "");
	assertText(`!image.png -right`, `<p class="blockimage right"><img alt="image.png" src="https://example.org/image.png"/></p>`,                           "");
	assertText(`!image.png -link http://example.org/`,
		`<p class="blockimage"><a href="http://example.org/"><img alt="image.png" src="https://example.org/image.png"/></a></p>`,                           "");
	assertText(`!!"URL contains whitespace.jpg"`,
		`<p class="blockimage wide"><img alt="URL contains whitespace.jpg" src="https://example.org/URL contains whitespace.jpg"/></p>`,                    "");
	assertText(`!https://upload.wikimedia.org/wikipedia/en/d/da/D_programming_language_logo.png -alt "External image"`,
		`<p class="blockimage"><img alt="External image" src="https://upload.wikimedia.org/wikipedia/en/d/da/D_programming_language_logo.png"/></p>`,       "");
	// HTML
	assertText(`!im<br>age.png`,
		`<p class="blockimage"><img alt="im&lt;br&gt;age.png" src="https://example.org/im&lt;br&gt;age.png"/></p>`,                                         "");
	assertText(`!image.png -alt "Some <b>alt</b> text"`,
		`<p class="blockimage"><img alt="Some &lt;b&gt;alt&lt;/b&gt; text" src="https://example.org/image.png"/></p>`,                                      "");
	
	// Custom blocks
	assertText(`&Plugin_1`,                 `[[Plugin_1]]`, `[Plugin_1]`);
	assertText(`&Plugin_2 -with arguments`, `[[Plugin_2]]`, `[Plugin_2]`);
	
	// Escaping
	assertLine(`[no]**text**[/no]`,       `**text**`,                       `**text**`);
	assertLine(`[no]__text__[/no]`,       `__text__`,                       `__text__`);
	assertLine(`[no]~~text~~[/no]`,       `~~text~~`,                       `~~text~~`);
	assertLine("[no]`text`[/no]",         "`text`",                         "`text`");
	assertLine(`[no]((text))[/no]`,       `((text))`,                       `((text))`);
	assertLine(`[no][no]yes[/[/no]no]`,   `[no]yes[/no]`,                   `[no]yes[/no]`);
	assertLine(`[no]<b>&times;</b>[/no]`, `&lt;b&gt;&amp;times;&lt;/b&gt;`, `<b>&times;</b>`);
	
	// Start with dark wide images
	assertText("!!https://example.org/img.png -dark\n\nOne.\n\nTwo.\n\nThree.",
		"<p class=\"blockimage wide\"><img alt=\"img.png\" src=\"https://example.org/img.png\"/></p>\n\n<p>One.</p>\n\n<p>Two.</p>\n\n<p>Three.</p>",
		"One.\n\nTwo.\n\nThree.", OpeningType.DarkWideImage);
	assertText("!!https://example.org/img.png -dark\n\nOne.\n\nTwo.\n\n(((CUT)))\n\nThree.",
		"<p class=\"blockimage wide\"><img alt=\"img.png\" src=\"https://example.org/img.png\"/></p>\n\n<p>One.</p>\n\n<p>Two.</p>\n\n<div class=\"cut\">Читать дальше »</div>\n<div class=\"undercut\">\n\n<p>Three.</p>\n\n</div>",
		"One.\n\nTwo.\n\nThree.", OpeningType.DarkWideImage);
}
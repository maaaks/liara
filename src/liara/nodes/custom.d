module liara.nodes.custom;

import liara;
import liara.params;
import liara.runtime;


package string processNode_CustomBlock(bool htmlMode)(ParseTree p) {
	if (!htmlMode)
		return "["~p.matches[0]~"]\n\n";
	else
		try {
			string pluginName = p.matches[0];
			string pluginInput = p.matches.length>1 ? p.matches[1] : "";
			bool addLast = (parserParams.addClassLast && p.begin == rt.lastBlockBegin);
			return parserParams.makeBlock(pluginName, pluginInput, addLast);
		}
		catch (UnsupportedPluginException e) {
			// Return the raw code as is
			return p.input[p.begin..p.end];
		}
}
function apply_style(str) {
 
    // global declarations, at beginning of line
    str = str.replace(/^import\b/,keyword("import"))
    str = str.replace(/^alias\b/,keyword("alias")) 
    str = str.replace(/^class\b/,keyword("class"))    
    str = str.replace(/^global\b/,keyword("global"))   
    str = str.replace(/^return\b/,keyword("return"))
    str = str.replace(/^create\b/,keyword("create"))
    str = str.replace(/^release\b/,keyword("release"))
    str = str.replace(/^method\b/,keyword("method"))
    str = str.replace(/^function\b/,keyword("function"))

    // optional keywords
    str = str.replace(/\broutine\b/,keyword("routine"))  
    str = str.replace(/\bdriver\b/,keyword("driver"))
    str = str.replace(/\bmodule\b/,keyword("module"))
    str = str.replace(/\baspect\b/,keyword("aspect"))
    str = str.replace(/\brecover\b/,keyword("recover"))
    str = str.replace(/\bfinalize\b/,keyword("finalize"))
    str = str.replace(/\bprocess\b/,keyword("process"))  
    str = str.replace(/\binit\b/,keyword("init"))  

    // mandatory 2 space intentation
    str = str.replace(/\s\sreturn\b/,keytab("  return"))
    str = str.replace(/\s\smethod\b/,keytab("  method"))
    str = str.replace(/\s\screate\b/,keytab("  create"))
    str = str.replace(/\s\srelease\b/,keytab("  release"))
    str = str.replace(/\s\sfunction\b/,keytab("  function"))

    // keywords in statement     
    str = str.replace(/\bsession\b/,keytab("session"))
    str = str.replace(/\bupdate\b/,keytab("update"))
    str = str.replace(/\bappend\b/,keytab("append"))
    str = str.replace(/\bcommit\b/,keytab("commit")) 
    str = str.replace(/\bfrom\b/,keytab("from"))
    str = str.replace(/\buse\b/,keytab("use"))

    // keyword operators  
    str = str.replace(/\bin\b/g,keytab("in"))     
    str = str.replace(/\bis\b/g,keytab("is"))
    str = str.replace(/\bas\b/g,keytab("as"))    
    str = str.replace(/\bor\b/g,keytab("or"))
    str = str.replace(/\beq\b/g,keytab("eq"))    
    str = str.replace(/\band\b/g,keytab("and"))
    str = str.replace(/\bnot\b/g,keytab("not"))


    // mandatory two space indentation
    str = str.replace(/\bnew\b/g,keytab("new"))
    str = str.replace(/\blet\b/g,keytab("let"))
    str = str.replace(/\bset\b/g,keytab("set"))
    
    // database singular statements
    str = str.replace(/\bscrub\b/g,keytab("scrub"))
    str = str.replace(/\bdelete\b/g,keytab("delete"))

    //  creat control flow
    str = str.replace(/\bbegin\b/,control("begin"))   
    str = str.replace(/\bcycle\b/,control("cycle"))
    str = str.replace(/\brepeat\b/,control("repeat"))    
    str = str.replace(/\bwhen\b/,control("when"))
    str = str.replace(/\bjob\b/,control("job"))
    str = str.replace(/\bcase\b/,control("case"))  
    str = str.replace(/\bon\b/,control("on"))    
    str = str.replace(/\bloop\b/,control("loop"))
    str = str.replace(/\bwhile\b/,control("while"))
    str = str.replace(/\bfor\b/,control("for"))
    str = str.replace(/\btask\b/,control("task"))
    str = str.replace(/\btry\b/,control("try"))
    str = str.replace(/\bmiss\b/,control("miss"))
    str = str.replace(/\bmatch\b/,control("match"))
    str = str.replace(/\bif\b/g,control("if"))
    str = str.replace(/\bthen\b/,control("then"))
    str = str.replace(/\belse\b/g,control("else"))
    str = str.replace(/\bdone\b/g,control("done"))

    // colorize data types keywords
    str = str.replace(/\bByte\b/g,types("Byte"))
    str = str.replace(/\bShort\b/g,types("Short"))
    str = str.replace(/\bInteger\b/g,types("Integer"))
    str = str.replace(/\bNatural\b/g,types("Natural"))
    str = str.replace(/\bDouble\b/g,types("Double"))
    str = str.replace(/\bFloat\b/g,types("Float"))
    str = str.replace(/\bRational\b/g,types("Rational"))
    str = str.replace(/\bString\b/g,types("String"))
    str = str.replace(/\bLogic\b/g,types("Logic"))
    str = str.replace(/\bTable\b/g,types("Table"))
    str = str.replace(/\bSymbol\b/g,types("Symbol"))
    str = str.replace(/\bRecord\b/g,types("Record"))
    str = str.replace(/\bOrdinal\b/g,types("Ordinal"))
    str = str.replace(/\bVariant\b/g,types("Variant"))
    str = str.replace(/\bDate\b/g,types("Date"))
    str = str.replace(/\bTime\b/g,types("Time"))
    str = str.replace(/\bArray\b/g,types("Array")) 
    str = str.replace(/\bList\b/g,types("List"))
    str = str.replace(/\bSymbol\b/g,types("Symbol"))
    str = str.replace(/\bObject\b/g,types("Object"))
    str = str.replace(/\bClass\b/g,types("Class"))
    str = str.replace(/\bLambda\b/g,types("Lambda"))
    str = str.replace(/\bFunction\b/g,types("Function"))   
    str = str.replace(/\bDataSet\b/g,types("DataSet"))
    str = str.replace(/\bHashMap\b/g,types("HashMap"))

    // reserved types
    str = str.replace(/\bNull\b/g,types("Null"))
    str = str.replace(/\bTrue\b/g,types("True"))
    str = str.replace(/\bFalse\b/g,types("False"))
    str = str.replace(/\bType\b/g,types("Type")) 

    // reserved constants
    str = str.replace(/\bany\b/g,constant("any"))
    str = str.replace(/\bother\b/g,constant("other"))
    str = str.replace(/\ball\b/g,constant("all"))
    str = str.replace(/\bone\b/g,constant("one"))
    str = str.replace(/\blabel\b/g,constant("label"))
    str = str.replace(/\bself\b/g,constant("self"))
    str = str.replace(/\bargs\b/g,constant("args"))
    str = str.replace(/\bsuper\b/g,constant("super"))

    //  interruption statements
    str = str.replace(/\bexpect\b/,keytab("expect"))
    str = str.replace(/\bbreak\b/,keytab("break"))
    str = str.replace(/\bhalt\b/,keytab("halt"))
    str = str.replace(/\bnext\b/,keytab("next"))
    str = str.replace(/\balter\b/,keytab("alter"))
    str = str.replace(/\bmake\b/,keytab("make"))
    str = str.replace(/\bstore\b/,keytab("store"))
    str = str.replace(/\bapply\b/,keytab("apply"))
    str = str.replace(/\bstart\b/,keytab("start"))
    str = str.replace(/\byield\b/,keytab("yield"))
    str = str.replace(/\brun\b/,keytab("run"))
    str = str.replace(/\bcall\b/,keytab("call"))
    str = str.replace(/\bwait\b/,keytab("wait"))
    str = str.replace(/\bexit\b/,keytab("exit"))
    str = str.replace(/\babort\b/,keytab("abort"))
    str = str.replace(/\bprint\b/,keytab("print"))
    str = str.replace(/\bwrite\b/,keytab("write"))
    str = str.replace(/\bread\b/,keytab("read"))
    str = str.replace(/\bover\b/,keytab("over"))
    str = str.replace(/\bpanic\b/,keytab("panic"))
    str = str.replace(/\bpass\b/,keytab("pass"))
    str = str.replace(/\bskip\b/,keytab("skip"))
    str = str.replace(/\bfail\b/,keytab("fail"))
    str = str.replace(/\braise\b/,keytab("raise"))
    str = str.replace(/\bretry\b/,keytab("retry"))
    str = str.replace(/\bresume\b/,keytab("resume"))
    str = str.replace(/\bsynchronise\b/,keytab("synchronise"))
    str = str.replace(/\brollback\b/,keytab("rollback"))

    // two symbol operators
    str = str.replace(/::/g,operator("::"))
    str = str.replace(/:=/g,operator(":="))
    str = str.replace(/==/g,operator("==")) 
    str = str.replace(/!=/g,operator("!="))    
    str = str.replace(/=>/g,operator("=>"))

    str = str.replace(/:>/g,operator(":>"))
    str = str.replace(/<:/g,operator("<:"))
    str = str.replace(/<-/g,operator("<-"))
    str = str.replace(/->/g,operator("->"))

    // replace range operator
    str = str.replace(/\.\.\./g,operator("..."))
    str = str.replace(/\.\./g,operator(".."))

    // two symbol modifiers
    str = str.replace(/\*=/g,operator("*="))
    str = str.replace(/\/=/g,operator("/="))
    str = str.replace(/\-=/g,operator("-="))
    str = str.replace(/\+=/g,operator("+="))    
    str = str.replace(/\^=/g,operator("^="))  
    str = str.replace(/\%=/g,operator("%=")) 

    //problematic operators
    str = str.replace(/ <= /g,operator(" <= "))
    str = str.replace(/ >= /g,operator(" >= "))    
    str = str.replace(/ << /g,operator(" << ")) 
    str = str.replace(/ >> /g,operator(" >> ")) 

    // supertype & coercion
    str = str.replace(/<\+/g,operator("<+"))
    str = str.replace(/\+>/g,operator("+>"))

    // fix encoded symbols
    str = str.replace(/\b=\&gt;\b/g,operator("=&gt;"))
    str = str.replace(/\b\&lt;\:\b/g,operator("&lt;:")) 
    str = str.replace(/\b\:\&gt;\b/g,operator(":&gt;"))  
    str = str.replace(/\b\.&\.\b/g,operator(".&."))
    str = str.replace(/\b\.\|\.\b/g,operator(".|."))
    str = str.replace(/\b\.\+\.\b/g,operator(".+."))
    str = str.replace(/\b-\&gt;\b/g,operator("-&gt;"))
    str = str.replace(/\b\&lt;-\b/g,operator("&lt;-"))


    //prefix
    str = str.replace(/\*(?=\w)/g,operator("*"))
    str = str.replace(/\@(?=\S)/g,operator("@"))  

    //sigils
    str = str.replace(/\$(?=\w)/g,operator("$"))    
    str = str.replace(/\_(?=\W)/g,operator("_"))

    //fix single simbol
    str = str.replace(/\?(?=\s|\b|\w)/,operator("?"))
    str = str.replace(/\:(?=\s|\b|$)/,operator(":"))
    str = str.replace(/\:(?=\s|\w|\W|[\{\[\(])/g,operator(":"))
    str = str.replace(/\;(?=\s|\b|$)/,operator(";")) 

    //fix concatenation
    str = str.replace(/\"\/\"/,operator("/"))

    //fix operators
    str = str.replace(/\s=\s/g,operator(" = "))
    str = str.replace(/\s>\s/g,operator(" > "))
    str = str.replace(/\s<\s/g,operator(" < "))
    str = str.replace(/\s\+\s/g,operator(" + "))
    str = str.replace(/\s\-\s/g,operator(" - "))
    str = str.replace(/\s\/\s/g,operator(" / "))
    str = str.replace(/\s\*\s/g,operator(" * "))
    str = str.replace(/\s\&\s/g,operator(" & "))
    str = str.replace(/\s\|\s/g,operator(" | "))

    // special indexes
    str = str.replace(/\*(?=\W)/g,operator("*"))
    str = str.replace(/\#(?=\W)/g,operator("#"))
    str = str.replace(/\?(?=\W)/g,operator("?"))

    // stile single quoted symbols 
    // squote is a callback function
    str = str.replace(/\'.\'/g, squote)

    // create the new statement
    return str
}

//style double quoted string
function style_string(line) {
    let result = ""
    let q = 0
    let chars = line.split("")
    let stmt  = [] //statement buffer
    let strg  = [] //string buffer
    let pchar = "" //previous character
    let instr = false;
    for (char of chars) {   
        if ((char == '"') && (pchar != "\\")) {
           if (instr == true) {
              result  += strings('"'+strg.join("")+'"') 
              strg     = [] // flush string buffer
           } else {
              result  += apply_style(stmt.join(""))
              stmt     = [] // flush statement buffer
           }
           q +=1 // new quote (no escape \")
           instr = (q % 2 > 0);
        } else if (instr == true) {
           strg.push(char) 
        } else {
           stmt.push(char)
        }
        pchar = char // look back
    }
    //fix the result 
    if (stmt.length > 0) {
        result += apply_style(stmt.join("")) 
    }
    if (strg.length > 0) {
        result += strings('"'+strg.join("")+'"')
    }   
    return result
}

//stile single goted strings
function squote(match, offset, string) {
  return strings(match);
}

/* it is called in every eve page at on-load event */
function eve_render() {
    const eve_code = document.getElementsByClassName("language-eve");
    if (typeof(eve_code) != "undefined") {
        let t = ""
        let i = 0 
        let q = 0 // how meny qotes
        let pozition = 0
        let comment = ""
        let start_comments = false
        let start_string   = false   
        let my_string = ""
        for (e of eve_code ) {
            if (e.tagName =="CODE") {
                lines = e.innerText.split("\n")
                //  format each line
                for (line of lines) {
                    // check if line is empty
                    if (i == 0 && line =="") {
                        i += 1
                        continue
                    }
                    // check first character
                    if (line.trim().substr(0,1)=="#") {
                        line = title(line)
                    } else if (line.trim().substr(0,2)=="**") {
                        line = subtitle(line)
                    } else if (line.trim().substr(0,2)=="--") {
                        line = comments(line) 
                    } else if ((line.trim().substr(0,2)=="/*") || 
                               (line.trim().substr(0,2)=="+-") ||
                                start_comments)
                               {
                        start_comments = true
                    } else if (line.search(/=\s*"""/g)>0) {
                        parts=line.split('"""')
                        my_string = '"""'+parts[1]
                        line = apply_style(parts[0])
                        start_string = true
                    } else if (line.search(/"""/g)>0) {
                        parts=line.split('"""')
                        line = strings(parts[0]+'"""')+parts[1]     
                        start_string = false  
                        my_string=""                
                    } else if (start_string) {
                        line  = strings(line)              
                    } else {
                        // split away end comments 
                        parts = line.split(/\s--/)
                        line  = parts[0]
                        if (parts.length > 1) {
                            comment = " --" + parts[1]
                        } else {
                            comment = ""
                        }
                        // style first part (before comment)
                        line = style_string(line);
                        // attach back the comment
                        if (comment!="") {
                            line += comments(comment)         
                        }  
                    }
                    // skip block comments from style
                    if (start_comments) {
                        if (line.search(/\*\//gm) > 0 ||
                            line.search(/\-\+/gm) > 0 ||
                            line.trim().substr(0,2)=="*/"||
                            line.trim().substr(0,2)=="-+") 
                        {
                            start_comments = false
                        } 
                        line = comments(line)
                    } else if (start_string) {
                        if (my_string) {
                           line = line + strings(my_string)
                        } else {
                           line = strings(line) 
                        }
                        my_string =""
                    }

                    // add new line if required
                    i += 1
                    if (i < lines.length || line!="") {
                       t += line_span(line)
                    }
                } // end for (line of lines)
                e.innerHTML = t;
                t = ""; i = 0
            } // end if (e.tagName =="CODE") 
        } // end for (e of eve_code )
    } else {
      console.log("not_found")
    }
}

function line_span(str) {
    var span = document.createElement("span");
    return "<span class=\"line\">"+ str + "</span>"
}


function title(str) {
    return "<span class=\"title\">"+ str + "</span>"
}

function subtitle(str) {
    return "<span class=\"subtitle\">"+ str + "</span>"
}

function comments(str) {
    return "<span class=\"comment\">"+ str + "</span>"
}

function keyword(str) {
    return "<span class=\"keyword\">"+ str + "</span>"
}

function keytab(str) {
    return "<span class=\"keytab\">"+ str + "</span>"
}

function types(str) {
    return "<span class=\"type\">"+ str + "</span>"
}

function control(str) {
    return "<span class=\"control\">"+ str + "</span>"
}

function interrupt(str) {
    return "<span class=\"interrupt\">"+ str + "</span>"
}

function operator(str) {
    return "<span class=\"operator\">"+ str + "</span>"
}

function strings(str) {
    return "<span class=\"string\">"+ str + "</span>"
}


function constant(str) {
    return "<span class=\"constant\">"+ str + "</span>"
}

function builtin(str) {
    return "<span class=\"builtin\">"+ str + "</span>"
}

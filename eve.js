function apply_style(str) {
    // global declarations
    str = str.replace(/^driver\b/,keyword("driver"))
    str = str.replace(/^module\b/,keyword("module"))
    str = str.replace(/^aspect\b/,keyword("aspect"))
    str = str.replace(/^import\b/,keyword("import"))
    str = str.replace(/^alias\b/,keyword("alias"))
    str = str.replace(/^lambda\b/,keyword("lambda"))    
    str = str.replace(/^class\b/,keyword("class"))    
    str = str.replace(/^global\b/,keyword("global"))   
    str = str.replace(/^process\b/,keyword("process"))  
    str = str.replace(/^reset\b/,keyword("reset"))  

    // maybe with indentation     
    str = str.replace(/\bcreate\b/,keyword("create"))
    str = str.replace(/\brelease\b/,keyword("release"))
    str = str.replace(/\bmethod\b/,keyword("method"))
    str = str.replace(/\bfunction\b/,keyword("function"))
    str = str.replace(/\breturn\b/,keyword("return"))
    str = str.replace(/\brecover\b/,keyword("recover"))
    str = str.replace(/\brelease\b/,keyword("release"))
    str = str.replace(/\bfinalize\b/,keyword("finalize"))
    str = str.replace(/\breport\b/,keyword("report"))   
    str = str.replace(/\bsession\b/,keyword("session"))
    str = str.replace(/\bupdate\b/,keyword("update"))
    str = str.replace(/\bappend\b/,keyword("append"))
    str = str.replace(/\bon\b/,keyword("on"))
    str = str.replace(/\bcommit\b/,keyword("commit"))     
    // in statement
    str = str.replace(/\bfrom\b/,keyword("from"))
    str = str.replace(/\buse\b/,keyword("use"))

    //  creat control flow
    str = str.replace(/\bbegin\b/,control("begin"))   
    str = str.replace(/\bcycle\b/,control("cycle"))
    str = str.replace(/\brepeat\b/,control("repeat"))    
    str = str.replace(/\bwhen\b/,control("when"))
    str = str.replace(/\bjob\b/,control("job"))
    str = str.replace(/\bcase\b/,control("case"))   
    str = str.replace(/\bother\b/,control("other"))
    str = str.replace(/\bloop\b/,control("loop"))
    str = str.replace(/\bwhile\b/,control("while"))
    str = str.replace(/\bfor\b/,control("for"))
    str = str.replace(/\btask\b/,control("task"))
    str = str.replace(/\btry\b/,control("try"))
    str = str.replace(/\bmiss\b/,control("miss"))
    str = str.replace(/\bmatch\b/,control("match"))
    str = str.replace(/\ball\b/g,control("all"))
    str = str.replace(/\bone\b/g,control("one"))
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
    str = str.replace(/\bNull\b/g,types("Null"))
    str = str.replace(/\bTrue\b/g,types("True"))
    str = str.replace(/\bFalse\b/g,types("False"))
    str = str.replace(/\bType\b/g,types("Type")) 
      
    //  interruption statements
    str = str.replace(/\bexpect\b/,interrupt("expect"))
    str = str.replace(/\bbreak\b/,interrupt("break"))
    str = str.replace(/\bnext\b/,interrupt("next"))
    str = str.replace(/\balter\b/,interrupt("alter"))
    str = str.replace(/\bmake\b/,interrupt("make"))
    str = str.replace(/\bstore\b/,interrupt("store"))
    str = str.replace(/\bapply\b/,interrupt("apply"))
    str = str.replace(/\bcall\b/,interrupt("call"))
    str = str.replace(/\bwait\b/,interrupt("wait"))
    str = str.replace(/\bexit\b/,interrupt("exit"))
    str = str.replace(/\babort\b/,interrupt("abort"))
    str = str.replace(/\bprint\b/,interrupt("print"))
    str = str.replace(/\bwrite\b/,interrupt("write"))
    str = str.replace(/\bread\b/,interrupt("read"))
    str = str.replace(/\bover\b/,interrupt("over"))
    str = str.replace(/\bpass\b/,interrupt("pass"))
    str = str.replace(/\bskip\b/,interrupt("skip"))
    str = str.replace(/\bfail\b/,interrupt("fail"))
    str = str.replace(/\braise\b/,interrupt("raise"))
    str = str.replace(/\bretry\b/,interrupt("retry"))
    str = str.replace(/\brollback\b/,interrupt("rollback"))
    // operators   
    str = str.replace(/\bin\b/g,operator("in"))     
    str = str.replace(/\bis\b/g,operator("is"))
    str = str.replace(/\bas\b/g,operator("as"))    
    str = str.replace(/\bor\b/g,operator("or"))
    str = str.replace(/\beq\b/g,operator("eq"))    
    str = str.replace(/\band\b/g,operator("and"))
    str = str.replace(/\bnot\b/g,operator("not"))
    
    // mandatory indentation
    str = str.replace(/\snew\b/g,operator(" new"))
    str = str.replace(/\slet\b/g,operator(" let"))
    str = str.replace(/\sset\b/g,operator(" set"))

    // two symbols
    str = str.replace(/\s::\s/g,operator(" :: "))
    str = str.replace(/\s:=\s/g,operator(" := "))
    str = str.replace(/\s==\s/g,operator(" == ")) 
    str = str.replace(/\s!=\s/g,operator(" != "))    
    str = str.replace(/\s=>\s/g,operator(" => "))
    str = str.replace(/\s<=\s/g,operator(" <= "))
    str = str.replace(/\s>=\s/g,operator(" >= "))
    str = str.replace(/\s:>\s/g,operator(" :> "))
    str = str.replace(/\s<:\s/g,operator(" <: "))
    str = str.replace(/\s<-\s/g,operator(" <- "))
    str = str.replace(/\s->\s/g,operator(" -> "))

    // modifiers
    str = str.replace(/\s\*=\s/g,operator(" *= "))
    str = str.replace(/\s\/=\s/g,operator(" /= "))
    str = str.replace(/\s\-=\s/g,operator(" -= "))
    str = str.replace(/\s\+=\s/g,operator(" += "))    
    str = str.replace(/\s\^=\s/g,operator(" ^= "))  
    str = str.replace(/\s\%=\s/g,operator(" %= ")) 

    //shift operators 
    str = str.replace(/\s<<\s/g,operator(" << ")) 
    str = str.replace(/\s>>\s/g,operator(" >> ")) 

    // supertype & coercion
    str = str.replace(/\s<\+\s/g,operator(" <+ "))
    str = str.replace(/\s\+>\s/g,operator(" +> "))

    // fix encoded symbols
    str = str.replace(/\b=\&gt;\b/g,operator("=&gt;"))
    str = str.replace(/\b\&lt;\:\b/g,operator("&lt;:")) 
    str = str.replace(/\b\:\&gt;\b/g,operator(":&gt;"))  
    str = str.replace(/\b\.&\.\b/g,operator(".&."))
    str = str.replace(/\b\.\|\.\b/g,operator(".|."))
    str = str.replace(/\b\.\+\.\b/g,operator(".+."))
    str = str.replace(/\b-\&gt;\b/g,operator("-&gt;"))
    str = str.replace(/\b\&lt;-\b/g,operator("&lt;-"))

    //sigil or prefix
    str = str.replace(/\*(?=\w)/g,operator("*"))
    str = str.replace(/\@(?=\w)/g,operator("@"))
    str = str.replace(/\$(?=\w)/g,operator("$"))
    str = str.replace(/\s_(?=\w)/g,operator(" _"))
    str = str.replace(/\s\.(?=\w)/g,operator(" ."))

    //fix single simbol
    str = str.replace(/\?(?=\s|\b|\w)/,operator("?"))
    str = str.replace(/:(?=\s|\b|$)/,operator(":"))
    str = str.replace(/:(?=\s|\w|\W|[\{\[\(])/g,operator(":"))
    str = str.replace(/;(?=\s|\b|$)/,operator(";")) 

    //fix concatenation
    str = str.replace(/(?<=\w)\/(?=\w|\b|\$)/,operator("/"))

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

    // stile single quoted symbols
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
                        parts = line.split(/(?<!['"])--/)
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

function builtin(str) {
    return "<span class=\"builtin\">"+ str + "</span>"
}

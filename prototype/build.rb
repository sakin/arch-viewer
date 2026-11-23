# PROTOTYPE: inline ir.json into template.html -> index.html
json = File.read("ir.json").gsub("</", "<\\/")
File.write("index.html", File.read("template.html").sub("/*IR*/null") { json })

AbstractTemplateCompiler = require './template'
handlebars = require 'handlebars'
fs = require 'fs'
path = require 'path'

module.exports = class HandlebarsCompiler extends AbstractTemplateCompiler

  clientLibrary: "handlebars"

  @prettyName        = -> "Handlebars"
  @defaultExtensions = -> ["hbs", "handlebars"]

  constructor: (config) -> super(config)

  compile: (fileNames, callback) ->
    error = null

    helperPath = path.join(@srcDir, @config.helperFile + ".coffee")
    defines = ["'#{@clientLibrary}'"]
    if path.existsSync(helperPath)
      helperDefine = @config.helperFile.replace /(^[\\\/]?[A-Za-z]+[\\\/])/, ''
      defines.push "'#{helperDefine}'"
    defineString = defines.join ','

    output = """
             define([#{defineString}], function (Handlebars){
               if (!Handlebars) {
                 console.log("Handlebars library has not been passed in successfully via require");
                 return;
               }
               var template = Handlebars.template, templates = {};\n
             """

    for fileName in fileNames
      content = fs.readFileSync fileName, "ascii"
      templateName = path.basename(fileName, path.extname(fileName))
      try
        templateOutput = handlebars.precompile(content)
        output += "templates['#{templateName}'] = template(#{templateOutput});\n"
      catch err
        error += "#{err} \n"

    output += 'return templates; });'

    callback(error, output)
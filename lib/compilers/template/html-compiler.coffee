fs = require 'fs'
path = require 'path'

_ = require 'underscore'

AbstractTemplateCompiler = require './template'
logger = require '../../util/logger'

module.exports = class HTMLCompiler extends AbstractTemplateCompiler

  clientLibrary: null

  @prettyName        = "HTML - Just Plain HTML Snippets, no compiling"
  @defaultExtensions = ["template"]

  constructor: (config, @extensions) ->
    super(config)

  compile: (fileNames, callback) ->
    error = null

    # we don't want underscore to actually work, just to wrap stuff
    _.templateSettings =
      evaluate    : /<%%%%%%%%([\s\S]+?)%%%%%%%>/g,
      interpolate : /<%%%%%%%%=([\s\S]+?)%%%%%%%>/g

    output = "define(function () { var templates = {};\n"
    for fileName in fileNames
      logger.debug "Compiling HTML template [[ #{fileName} ]]"
      content = fs.readFileSync fileName, "ascii"
      compiledOutput = _.template(content)
      templateName = path.basename(fileName, path.extname(fileName))
      output += @addTemplateToOutput fileName, templateName, compiledOutput.source + "()"
    output += 'return templates; });'

    # set it back
    _.templateSettings =
      evaluate    : /<%([\s\S]+?)%>/g,
      interpolate : /<%=([\s\S]+?)%>/g

    callback(error, output)
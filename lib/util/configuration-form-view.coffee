FormView = require './form-view'
Configuration = require './configuration.coffee'

class ConfigurationFormView extends FormView

  initialize: ->
    super

    @addRow @createFieldRow("contentDir", "directory", Configuration.labels.contentDir)
    @addRow @createFieldRow("targetDir", "directory", Configuration.labels.targetDir)

module.exports = document.registerElement('mpw-configuration-form-view',
  prototype: ConfigurationFormView.prototype,
  extends: 'div')

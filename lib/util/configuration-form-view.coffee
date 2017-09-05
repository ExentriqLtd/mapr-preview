FormView = require './form-view'
Configuration = require './configuration.coffee'

class ConfigurationFormView extends FormView

  initialize: ->
    super

    @addRow @createTitleRow("MapR Preview Configuration")
    @addRow @createFieldRow("repoUrl", "text", Configuration.labels.repoUrl)
    @addRow @createFieldRow("contentDir", "directory", Configuration.labels.contentDir)
    @addRow @createFieldRow("targetDir", "directory", Configuration.labels.targetDir)
    @addRow @createFieldRow("repoOwner", "text", Configuration.labels.repoOwner)
    @addRow @createFieldRow("username", "text", Configuration.labels.username)
    @addRow @createFieldRow("password", "password", Configuration.labels.password)

module.exports = document.registerElement('mpw-configuration-form-view',
  prototype: ConfigurationFormView.prototype,
  extends: 'div')

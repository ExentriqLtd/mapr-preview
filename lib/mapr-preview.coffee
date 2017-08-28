ConfigurationView = require './configuration-view'
Configuration = require './util/configuration'
{CompositeDisposable} = require 'atom'

module.exports = MaprPreview =
  maprPreviewView: null
  panel: null
  subscriptions: null
  configuration: null

  consumeToolBar: (getToolBar) ->
    @toolBar = getToolBar('mapr-preview')
    @toolBar.addSpacer
      priority: 99

    @toolBar.addButton
      icon: 'device-desktop',
      callback: 'mapr-preview:preview',
      tooltip: 'MapR Preview'
      priority: 100

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'mapr-preview:toggle': => @toggle()

  configure: ->
    console.log 'MaprPreview shown configuration'
    @configuration = new Configuration()
    @configurationView = new ConfigurationView(@configuration(),
      () => @saveConfig(),
      () => @hideConfigure()
    )
    @panel = atom.workspace.addTopPanel(item: @configurationView.getElement(), visible: false) if !@panel?
    @panel.show()

  saveConfig: ->
    console.log "MaprPreview Save configuration"
    confValues = @configurationView.readConfiguration()
    @configuration.set(confValues)

    validationMessages = @configuration.validateAll().map (k) ->
      Configuration.reasons[k]
    if validationMessages.length == 0
      @configuration.save()
      @hideConfigure()

      #TODO: go on with preview
    else
      validationMessages.forEach (msg) ->
        atom.notifications.addError(msg)

  hideConfigure: ->
    console.log 'MaprPreview hidden configuration'
    @panel.destroy()
    @panel = null

  deactivate: ->
    @modalPanel.destroy()
    @subscriptions.dispose()
    @maprPreviewView.destroy()

  serialize: ->

  toggle: ->
    console.log 'MaprPreview was toggled!'

    if @modalPanel.isVisible()
      @modalPanel.hide()
    else
      @modalPanel.show()

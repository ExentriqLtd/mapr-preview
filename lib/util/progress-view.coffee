FormView = require './form-view'

class ProgressView extends FormView

  constructor: () ->

  initialize: () ->
    super
    @addRow @createFieldRow("progress", "progress", "Downloading repository... ")

  setProgress: (valuePercent) ->
    progress = @fields.find (f) -> f.getAttribute("type") == "progress"
    if !progress
      return
    # console.log @fields, progress
    progress.value = valuePercent

module.exports = document.registerElement 'mpw-progress-view',
  prototype: ProgressView.prototype, extends: 'div'

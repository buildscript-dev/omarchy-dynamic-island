import Quickshell
import Quickshell.Io
import "IslandModel.js" as Model

// Every Process the island starts: the closed environment from IslandModel.js.
// Give it a command built with Model.bounded() so it also has a deadline and an
// output cap.
Process {
  environment: Model.childEnv(function(k) { return Quickshell.env(k) })
  clearEnvironment: true
}

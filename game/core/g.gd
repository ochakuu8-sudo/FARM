extends RefCounted
## ゲーム全体から参照する入れ物。project の autoload を使うと管理ツールの起動にも載るため、ここに静的に持つ。
static var main: Node      # game/main.gd
static var db               # game/core/db.gd
static var state            # game/core/state.gd
static var anim             # game/core/anim.gd
static var settings: Dictionary={}

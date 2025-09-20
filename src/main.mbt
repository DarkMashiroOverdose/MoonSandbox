// ---------------------------------
//  全局状态与实体
// ---------------------------------
struct GameState {
  selected_entities: Array[@system.Entity]
}
let game_state: GameState = { selected_entities: [] }

let destinations: Map[@system.Entity, @math.Vec2D] = Map::new()
let all_units: Ref[Array[@system.Entity]] = Ref::new([])

let is_dragging: Ref[Bool] = Ref::new(false) // 记录是否正在拖动
let drag_start_pos: Ref[@math.Vec2D] = Ref::new(@math.Vec2D(0.0, 0.0)) // 记录拖动起始点

let drag_box_entity: @system.Entity = @system.Entity::new() // 新增：拖动框实体

let avoidance_behaviors: Map[@system.Entity, AvoidanceBehavior] = Map::new()
const FORMATION_SPACING: Double = 50.0 // 单位在队列中的间距
let entities_to_cleanup: Ref[Array[@system.Entity]] = Ref::new([])
const ENEMY_PUSH_FACTOR: Double = 3.0 // 敌我单位间的推力系数

struct AvoidanceBehavior {
  unit_radius: Double
  avoidance_radius: Double
}

enum Team {
  Player
  Enemy
} derive(Eq, Show)

let teams: Map[@system.Entity, Team] = Map::new()
// 用一个 Map 来存储拥有该组件的实体
// ---------------------------------
//  主函数 (Main Function)
// ---------------------------------
fn main {
  @system.App::new(@canvas.CanvasBackend::new())
    .with_canvas_width(800.0)
    .with_canvas_height(600.0)
    .with_fps(60)
    .add_system(init_game, schedule=@system.Schedule::Startup)
    .add_system(update_health_bars_system, schedule=@system.Schedule::Update)
    .add_system(update_selection_boxes_system, schedule=@system.Schedule::Update)
    .add_system(selection_system, schedule=@system.Schedule::Update)
    .add_system(@sprite.render_world_system, schedule=@system.Schedule::Render(0)) // 先画世界
    .add_system(@sprite.render_ui_system, schedule=@system.Schedule::Render(1))    // 再画UI
    //.add_system(move_order_system, schedule=@system.Schedule::Update)
    .add_system(player_train_management_system, schedule=@system.Schedule::Update)
    //.add_system(train_follow_system, schedule=@system.Schedule::Update)
    .add_system(player_control_system, schedule=@system.Schedule::Update)
    .add_system(aggro_system, schedule=@system.Schedule::Update)
    .add_system(combat_system, schedule=@system.Schedule::Update)
    .add_system(npc_intent_system, schedule=@system.Schedule::Update)
    .add_system(avoidance_system, schedule=@system.Schedule::Update)
    .add_system(velocity_resolver_system, schedule=@system.Schedule::Update)
    .add_system(projectile_system, schedule=@system.Schedule::Update) 
    .add_system(debuff_system, schedule=@system.Schedule::Update)     
    .add_system(cleanup_effects_system, schedule=@system.Schedule::Update)
    .add_system(@system.advanced_key_system, schedule=@system.Schedule::Update)
    .add_system(@system.advanced_mouse_system, schedule=@system.Schedule::Update)
    
    .add_system(cleanup_system, schedule=@system.Schedule::Update)
    .add_system(apply_velocity_system, schedule=@system.Schedule::Update)
    .run()
}

// ---------------------------------
//  初始化 (Initialization)
// ---------------------------------
fn init_game(backend: &@system.Backend) -> Unit {
  backend.preload_img("assets/gray_map.png")
  add_map()
  
  add_new_ball(@math.Vec2D(350.0, 500.0), Team::Player)
  add_new_block(@math.Vec2D(350.0, 500.0), Team::Player)
  add_new_ball(@math.Vec2D(350.0, 500.0), Team::Player)
  add_new_block(@math.Vec2D(350.0, 500.0), Team::Player)

  
  // 创建敌方单位，放在地图另一侧
  //add_new_tank(@math.Vec2D(300.0, 100.0), Team::Enemy)
  add_new_ellipse_x(@math.Vec2D(400.0, 100.0), Team::Enemy)
  //add_new_tank(@math.Vec2D(500.0, 100.0), Team::Enemy)
  add_new_ellipse_x(@math.Vec2D(300.0, 100.0), Team::Enemy)
  add_new_ellipse_x(@math.Vec2D(500.0, 100.0), Team::Enemy)
  //add_new_tank(@math.Vec2D(300.0, 100.0), Team::Enemy)
  //add_new_tank(@math.Vec2D(500.0, 100.0), Team::Enemy)
  
}

fn add_map() -> Unit {
  let map_entity = @system.Entity::new()
  @position.positions.set(map_entity, @math.Vec2D(0.0, 0.0))
  let map_picture = @sprite.Picture::new(
    @math.Vec2D(1048.0, 768.0), "assets/gray_map.png")
  let map_sprite = @sprite.Sprite::from_picture(map_picture, 0)
  @sprite.sprites.set(map_entity, map_sprite)
}

// ---------------------------------
//  系统 (Systems)
// ---------------------------------



// 我们需要一个 min_int 函数来辅助计算
fn min_int(a: Int, b: Int) -> Int {
  if a < b { a } else { b }
}


fn apply_velocity_system(_backend: &@system.Backend) -> Unit {
  for entity in @velocity.velocities.keys() {
    if @position.positions.get(entity) is Some(pos) {
      if @velocity.velocities.get(entity) is Some(vel) {
        let new_pos = pos.0 + vel.0
        @position.positions.set(entity, new_pos)
      }
    }
  }
}


const AVOIDANCE_STRENGTH: Double = 4


// ---------------------------------
//  全新的清理系统
// ---------------------------------
// ---------------------------------
//  全新的清理系统 (重构版)
// ---------------------------------
fn cleanup_system(_backend: &@system.Backend) -> Unit {
  if entities_to_cleanup.val.length() > 0 {
    // 1. 在清理组件前，先处理所有可能的断链逻辑
    for dead_unit in entities_to_cleanup.val {
      if teams.get(dead_unit) is Some(Team::Player) {
        // 调用我们新的“专家”函数
        relink_train_chain(dead_unit)
      }
    }

    // 2. 执行通用的、彻底的清理逻辑
    for dead_unit in entities_to_cleanup.val {
      println("[Log] Cleanup System is processing: \{dead_unit}")
      
      // 销毁所有视觉实体
      @system.Entity::destroy(dead_unit)
      if healths.get(dead_unit) is Some(health) {
        @system.Entity::destroy(health.bar_bg_entity)
        @system.Entity::destroy(health.bar_fg_entity)
      }
      if unit_to_selection_box.get(dead_unit) is Some(box) {
        @system.Entity::destroy(box)
      }

      // 从所有【渲染】相关的 Map 中移除组件
      @sprite.sprites.remove(dead_unit)
      if healths.get(dead_unit) is Some(health) {
          @sprite.sprites.remove(health.bar_bg_entity)
          @sprite.sprites.remove(health.bar_fg_entity)
      }
      if unit_to_selection_box.get(dead_unit) is Some(box) {
          @sprite.sprites.remove(box)
      }

      // 从所有【逻辑】相关的 Map 中移除组件
      healths.remove(dead_unit)
      combat_stats.remove(dead_unit)
      teams.remove(dead_unit)
      destinations.remove(dead_unit)
      attack_targets.remove(dead_unit)
      avoidance_behaviors.remove(dead_unit)
      unit_to_selection_box.remove(dead_unit)
      @position.positions.remove(dead_unit)
      @velocity.velocities.remove(dead_unit)
      train_cars.remove(dead_unit) // 别忘了移除 TrainCar 组件
    }

    // 3. 更新主逻辑列表
    all_units.val = all_units.val.filter(fn(unit) {
      !entities_to_cleanup.val.contains(unit)
    })
    
    // 4. 清空垃圾回收列表
    entities_to_cleanup.val.clear()
  }
}
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

const FORMATION_SPACING: Double = 50.0 // 单位在队列中的间距
let entities_to_cleanup: Ref[Array[@system.Entity]] = Ref::new([])

// --- 新增：用于存储背景音乐句柄的全局变量 ---
let bgm_handle: Ref[Option[@system.AudioHandle]] = Ref::new(None)

pub struct Size {
  radius: Double
}
pub let sizes: Map[@system.Entity, Size] = Map::new()

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
    .add_system(@sprite.render_world_system, schedule=@system.Schedule::Render(0)) // 先画世界
    .add_system(@sprite.render_ui_system, schedule=@system.Schedule::Render(1)) // 再画UI
    //.add_system(move_order_system, schedule=@system.Schedule::Update)
    .add_system(player_train_management_system, schedule=@system.Schedule::Update)
    //.add_system(train_follow_system, schedule=@system.Schedule::Update)
    .add_system(player_control_system, schedule=@system.Schedule::Update) // 1. 玩家输入，决定火车头速度
    .add_system(enemy_movement_system, schedule=@system.Schedule::Update) // 2. AI输入，决定敌人速度
    .add_system(aggro_system, schedule=@system.Schedule::Update) // 3. AI索敌
    .add_system(combat_system, schedule=@system.Schedule::Update) // 4. 战斗结算
    .add_system(projectile_system, schedule=@system.Schedule::Update) // 5. 抛射物飞行
    .add_system(unit_orientation_system, schedule=@system.Schedule::Update) // 状态旋转
    //.add_system(dynamic_transform_system, schedule=@system.Schedule::Update) // 旋转测试
    .add_system(hazardous_area_system, schedule=@system.Schedule::Update)//毒气区域
    .add_system(buff_system, schedule=@system.Schedule::Update) //buff
    
    .add_system(vfx_spawner_system, schedule=@system.Schedule::Update)
    .add_system(vfx_update_system, schedule=@system.Schedule::Update)
    // --- 执行与反馈层 ---
    .add_system(apply_velocity_system, schedule=@system.Schedule::Update) // 6. 应用所有速度，更新所有单位的【新位置】
    .add_system(path_history_system, schedule=@system.Schedule::Update) // 7. 录制所有玩家单位的【新位置】
    .add_system(train_snake_follow_system, schedule=@system.Schedule::Update) // 8. 【核心】根据新轨迹，直接设置车厢的【最终位置】
    // --- UI 与清理层 ---
    //.add_system(update_orientation_indicators_system, schedule=@system.Schedule::Update)
    .add_system(update_selection_boxes_system, schedule=@system.Schedule::Update)
    .add_system(update_health_bars_system, schedule=@system.Schedule::Update)
    .add_system(cleanup_system, schedule=@system.Schedule::Update)
    .add_system(@system.advanced_key_system, schedule=@system.Schedule::Update)
    .add_system(@system.advanced_mouse_system, schedule=@system.Schedule::Update)
    .run()
}

// ---------------------------------
//  初始化 (Initialization)
// ---------------------------------
fn init_game(backend: &@system.Backend) -> Unit {
  add_map()
  setup_vfx_library()

  // --- 新增：在游戏开始时播放并保存 BGM 句柄 ---
  let handle = @audio.play_audio(
    backend,
    "../assets/sfx/inst.mp3", // <-- 请替换为您的 BGM 文件路径
    volume=0.1, // 背景音乐音量通常小一些
    loop_=true,  // 背景音乐需要循环播放
  )
  bgm_handle.val = Some(handle)
  // ---------------------------------------------

  add_new_ball(@math.Vec2D(350.0, 500.0), Team::Player)
  add_new_block(@math.Vec2D(350.0, 500.0), Team::Player)
  add_new_ball(@math.Vec2D(350.0, 500.0), Team::Player)
  add_new_triangle(@math.Vec2D(350.0, 500.0), Team::Player)

  // 创建敌方单位，放在地图另一侧
  //add_new_tank(@math.Vec2D(300.0, 100.0), Team::Enemy)
  add_new_ellipse_x(@math.Vec2D(400.0, 100.0), Team::Enemy)
  add_new_ellipse_x(@math.Vec2D(300.0, 100.0), Team::Enemy)
  add_new_ellipse_x(@math.Vec2D(500.0, 100.0), Team::Enemy)
  //add_new_tank(@math.Vec2D(300.0, 100.0), Team::Enemy)
  //add_new_tank(@math.Vec2D(500.0, 100.0), Team::Enemy)
  add_rolling_triangle(@math.Vec2D(500.0, 200.0), Team::Enemy)
}

fn add_repeating_background() -> Unit {
  let map_width = 2000.0 // 例如，总宽度为 2000 像素
  let map_height = 1500.0 // 例如，总高度为 1500 像素

  let background_entity = @system.Entity::new()

  @position.positions.set(background_entity, @math.Vec2D::zero())

  let background_picture = @sprite.Picture::new(
    @math.Vec2D(map_width, map_height),
    "assets/background_tile.png",
    repeat=@system.RepeatMode::Repeat,
  )

  let background_sprite = @sprite.Sprite::from_picture(
    background_picture, 
    -100, 
  )

  @sprite.sprites.set(background_entity, background_sprite)
}
fn add_map() -> Unit {
  let map_entity = @system.Entity::new()
  @position.positions.set(map_entity, @math.Vec2D(-5.0, -5.0))
  //let map_picture = @sprite.Picture::new(
  //  @math.Vec2D(1048.0, 768.0), "assets/gray_map.png")
  //let map_sprite = @sprite.Sprite::from_picture(map_picture, 0)
  //let map_color = @sprite.ColoredShape::new(@sprite.Shape::rect(1048, 768, 0), @sprite.DrawStyle::fill("#000000"))
  //let map_sprite = @sprite.Sprite::from_shape(map_color, 100, layer=@sprite.RenderLayer::game_world())

  let background_entity = @system.Entity::new()

  @position.positions.set(background_entity, @math.Vec2D::zero())

  let background_picture = @sprite.Picture::new(
    @math.Vec2D(1965, 1085),
    "assets/background_tile.png",
    repeat=@system.RepeatMode::Repeat,
  )

  let map_sprite = @sprite.Sprite::from_picture(
    background_picture, 
    -100, 
  )
  
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

      // 从所有渲染相关的 Map 中移除组件
      @sprite.sprites.remove(dead_unit)
      if healths.get(dead_unit) is Some(health) {
        @sprite.sprites.remove(health.bar_bg_entity)
        @sprite.sprites.remove(health.bar_fg_entity)
      }
      if unit_to_selection_box.get(dead_unit) is Some(box) {
        @sprite.sprites.remove(box)
      }

      // 从所有逻辑相关的 Map 中移除组件
      healths.remove(dead_unit)
      combat_stats.remove(dead_unit)
      teams.remove(dead_unit)
      destinations.remove(dead_unit)
      attack_targets.remove(dead_unit)
      unit_to_selection_box.remove(dead_unit)
      @position.positions.remove(dead_unit)
      @velocity.velocities.remove(dead_unit)
      train_cars.remove(dead_unit) // 移除 TrainCar 组件
    }

    // 3. 更新主逻辑列表
    all_units.val = all_units.val.filter(fn(unit) {
      !entities_to_cleanup.val.contains(unit)
    })

    // 4. 清空垃圾回收列表
    entities_to_cleanup.val.clear()
  }
}


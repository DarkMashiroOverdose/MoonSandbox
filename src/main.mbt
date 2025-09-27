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
    // 1. 注册我们的“游戏世界总管”，它包含了所有可暂停的逻辑
    .add_system(update_game_world_system, schedule=@system.Schedule::Update)
    
    .add_system(@system.advanced_key_system, schedule=@system.Schedule::Update)
    .add_system(@system.advanced_mouse_system, schedule=@system.Schedule::Update)

    .add_system(pause_toggle_system, schedule=@system.Schedule::Update)

    .add_system(update_selection_boxes_system, schedule=@system.Schedule::Update)
    .add_system(update_health_bars_system, schedule=@system.Schedule::Update)

    .add_system(@sprite.render_world_system, schedule=@system.Schedule::Render(0)) // 先画世界
    .add_system(@sprite.render_ui_system, schedule=@system.Schedule::Render(1)) // 再画UI
    
    .run()
}
let is_paused: Ref[Bool] = Ref::new(false)

// --- 暂停控制系统 ---

// 这个系统专门监听暂停键，并且不应该被暂停
pub fn pause_toggle_system(_backend: &@system.Backend) -> Unit {
  // 检查玩家是否“刚刚按下”了 P 键
  if @system.is_just_pressed(@system.KeyP) {
    // 对 is_paused 的值进行取反 (true -> false, false -> true)
    is_paused.val = !is_paused.val
    
    if is_paused.val {
      println("[Game] Paused")
    } else {
      println("[Game] Resumed")
    }
  }
}

// --- 游戏世界总管系统 ---

// 这是所有“可暂停”的游戏逻辑系统的总入口
pub fn update_game_world_system(backend: &@system.Backend) -> Unit {
  guard !is_paused.val else { return }

  // 管理玩家小火车的连接状态
  player_train_management_system(backend)
  // 玩家输入，决定火车头的移动方向
  player_control_system(backend)
  // AI输入，决定敌人的移动方向
  enemy_movement_system(backend)
  // AI索敌，决定攻击目标
  aggro_system(backend)
  // 战斗结算，根据攻击目标和冷却，触发攻击效果
  combat_system(backend)
  // 更新所有飞行中的抛射物（子弹）的位置和方向
  projectile_system(backend)
  // 更新单位的视觉朝向（让Sprite朝向目标或移动方向）
  unit_orientation_system(backend)
  // 更新所有需要动态旋转/缩放的单位
  dynamic_transform_system(backend)
  // 更新所有持续伤害/效果区域
  hazardous_area_system(backend)
  // 更新所有Buff的持续时间
  buff_system(backend)
  // 根据时间生成新的敌人
  endless_spawner_system(backend)
  
  // 处理所有VFX的生成请求和生命周期
  vfx_spawner_system(backend)
  vfx_update_system(backend)

  // 这个阶段将所有单位的“意图”转化为实际的位置变化
  
  // 将所有单位的`velocity`应用到它们的`position`上
  apply_velocity_system(backend)
  // 为玩家小火车记录轨迹点
  path_history_system(backend)
  // 让车厢根据轨迹点进行跟随
  train_snake_follow_system(backend)

  // 移除所有被标记为“死亡”的实体和它们的组件
  cleanup_system(backend)
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


  spawn_timer.val = INITIAL_SPAWN_INTERVAL
  wave_count.val = 0
  // 创建敌方单位，放在地图另一侧
  //add_new_tank(@math.Vec2D(300.0, 100.0), Team::Enemy)
  //add_new_ellipse_x(@math.Vec2D(400.0, 100.0), Team::Enemy)
  ///add_rolling_capsule(@math.Vec2D(300.0, 100.0), Team::Enemy)
  //add_rolling_capsule(@math.Vec2D(500.0, 100.0), Team::Enemy)
  //add_rolling_cross(@math.Vec2D(360.0, 160.0), Team::Enemy)
  //add_new_tank(@math.Vec2D(500.0, 100.0), Team::Enemy)
  //add_rolling_triangle(@math.Vec2D(500.0, 200.0), Team::Enemy)
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


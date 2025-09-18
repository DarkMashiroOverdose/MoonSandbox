// ---------------------------------
//  全局状态与实体
// ---------------------------------
struct GameState {
  selected_entities: Array[@system.Entity]
}
let game_state: GameState = { selected_entities: [] }

let destinations: Map[@system.Entity, @math.Vec2D] = Map::new()
let all_units: Ref[Array[@system.Entity]] = Ref::new([])

// 一个 Map，用于存储每个作战单位 (key) 和它对应的选中框 (value)
let unit_to_selection_box: Map[@system.Entity, @system.Entity] = Map::new()

let is_dragging: Ref[Bool] = Ref::new(false) // 记录是否正在拖动
let drag_start_pos: Ref[@math.Vec2D] = Ref::new(@math.Vec2D(0.0, 0.0)) // 记录拖动起始点

let drag_box_entity: @system.Entity = @system.Entity::new() // 新增：拖动框实体

let avoidance_behaviors: Map[@system.Entity, AvoidanceBehavior] = Map::new()
const FORMATION_SPACING: Double = 50.0 // 单位在队列中的间距
let entities_to_cleanup: Ref[Array[@system.Entity]] = Ref::new([])
const ENEMY_PUSH_FACTOR: Double = 3.0 // 敌我单位间的推力系数
struct CombatStats {
  attack_range: Double    // 攻击范围
  attack_damage: Double   // 攻击伤害
  attack_cooldown: Double // 攻击间隔（秒）
  current_cooldown: Double // 当前的攻击冷却计时器
  aggro_range: Double // 【新增】警戒范围
}

// 用 Map 存储拥有该组件的实体
let combat_stats: Map[@system.Entity, CombatStats] = Map::new()

// 新增：用于存储“谁正在攻击谁”的 Map
// Key: 攻击者, Value: 被攻击的目标
let attack_targets: Map[@system.Entity, @system.Entity] = Map::new()

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
    .add_system(draw_drag_box_system, schedule=@system.Schedule::Render(2))
    .add_system(@sprite.render_world_system, schedule=@system.Schedule::Render(0)) // 先画世界
    .add_system(@sprite.render_ui_system, schedule=@system.Schedule::Render(1))    // 再画UI
    .add_system(move_order_system, schedule=@system.Schedule::Update)
    .add_system(aggro_system, schedule=@system.Schedule::Update)
    .add_system(combat_system, schedule=@system.Schedule::Update)
    .add_system(positioning_system, schedule=@system.Schedule::Update)
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
  backend.preload_img("assets/desert_map.png")
  backend.preload_img("assets/tank.png")
  add_map()
  
  add_new_tank(@math.Vec2D(350.0, 500.0), Team::Player)
  add_new_tank(@math.Vec2D(400.0, 500.0), Team::Player)
  add_new_tank(@math.Vec2D(450.0, 500.0), Team::Player)
  
  // 创建敌方单位，放在地图另一侧
  add_new_tank(@math.Vec2D(300.0, 100.0), Team::Enemy)
  add_new_tank(@math.Vec2D(400.0, 100.0), Team::Enemy)
  add_new_tank(@math.Vec2D(500.0, 100.0), Team::Enemy)
  
}

fn add_map() -> Unit {
  let map_entity = @system.Entity::new()
  @position.positions.set(map_entity, @math.Vec2D(0.0, 0.0))
  let map_picture = @sprite.Picture::new(
    @math.Vec2D(1048.0, 768.0), "assets/desert_map.png")
  let map_sprite = @sprite.Sprite::from_picture(map_picture, 0)
  @sprite.sprites.set(map_entity, map_sprite)
}

// ---------------------------------
//  系统 (Systems)
// ---------------------------------
fn update_selection_boxes_system(_backend: &@system.Backend) -> Unit {
  unit_to_selection_box.each(fn(unit, box_entity) {
    let is_selected = game_state.selected_entities.contains(unit)
    
    if @sprite.sprites.get(box_entity) is Some(sprite) {
      // 修正 #2: 使用正确的结构体更新语法
      let new_sprite = { ..sprite, visible: is_selected }
      @sprite.sprites.set(box_entity, new_sprite)
      
      if is_selected {
        if @position.positions.get(unit) is Some(unit_pos) {
          @position.positions.set(box_entity, unit_pos.0.add(@math.Vec2D(-2.0, -2.0)))
        }
      }
    }
  })
}

// (selection_system, move_order_system 等函数保持原样，无需修改)
fn selection_system(_backend: &@system.Backend) -> Unit {
  if @system.is_mouse_just_pressed(@system.MouseButton::Left) {
    is_dragging.val = true
    drag_start_pos.val = @system.mouse.pos
  }

  if @system.is_mouse_just_released(@system.MouseButton::Left) {
    is_dragging.val = false
    let drag_end_pos = @system.mouse.pos
    let start_pos = drag_start_pos.val

    let top_left_x = min_double(start_pos[X], drag_end_pos[X])
    let top_left_y = min_double(start_pos[Y], drag_end_pos[Y])
    let bottom_right_x = max_double(start_pos[X], drag_end_pos[X])
    let bottom_right_y = max_double(start_pos[Y], drag_end_pos[Y])

    game_state.selected_entities.clear()

    for unit in all_units.val {
      if @position.positions.get(unit) is Some(unit_pos) {
        let unit_center_x = unit_pos.0[X] + 32.0
        let unit_center_y = unit_pos.0[Y] + 32.0

        if unit_center_x >= top_left_x && unit_center_x <= bottom_right_x &&
           unit_center_y >= top_left_y && unit_center_y <= bottom_right_y {
          game_state.selected_entities.push(unit)
        }
      }
    }
  }
}
fn move_order_system(_backend: &@system.Backend) -> Unit {
  if @system.is_mouse_just_pressed(@system.MouseButton::Right) {
    let mouse_pos = @system.mouse.pos
    let mut clicked_on_enemy = None

    for unit in all_units.val {
      if @position.positions.get(unit) is Some(unit_pos) && teams.get(unit) is Some(unit_team) {
        let unit_x = unit_pos.0[X]
        let unit_y = unit_pos.0[Y]
        if mouse_pos[X] >= unit_x && mouse_pos[X] <= unit_x + 64.0 &&
           mouse_pos[Y] >= unit_y && mouse_pos[Y] <= unit_y + 64.0 {
          
          if unit_team == Team::Enemy {
            clicked_on_enemy = Some(unit)
            break
          }
        }
      }
    }

    if clicked_on_enemy is Some(target_entity) {
      // --- A. 是攻击指令 ---
      for selected_unit in game_state.selected_entities {
        if teams.get(selected_unit) is Some(Team::Player) {
          attack_targets.set(selected_unit, target_entity)
          destinations.remove(selected_unit)

          // 【新增日志】: 在这里打印攻击指令信息
          // 我们使用 \() 语法来在字符串中插入变量
          println("[Log] Attack Order Issued: Attacker \{selected_unit} -> Target \{target_entity}") 
        }
      }
    } else {
      // --- B. 是移动指令 ---
      for selected_unit in game_state.selected_entities {
        attack_targets.remove(selected_unit)
      }

      // 【新增日志】: 打印移动指令信息
      println("[Log] Move Order Issued. Clearing attack targets.")
      
      let selected_count = game_state.selected_entities.length()
      if selected_count > 0 {
        // ... 后面的队列移动代码保持不变 ...
        let target_center = mouse_pos
        let num_columns = 5
        let formation_width = (min_int(selected_count, num_columns) - 1).to_double() * FORMATION_SPACING
        let num_rows = (selected_count + num_columns - 1) / num_columns
        let formation_height = (num_rows - 1).to_double() * FORMATION_SPACING

        for i = 0; i < selected_count; i = i + 1 {
          let entity = game_state.selected_entities[i]
          let row = (i / num_columns).to_double()
          let col = (i % num_columns).to_double()
          let offset_x = col * FORMATION_SPACING - formation_width / 2.0
          let offset_y = row * FORMATION_SPACING - formation_height / 2.0
          let final_destination = target_center + @math.Vec2D(offset_x, offset_y)
          destinations.set(entity, final_destination)
        }
      }
    }
  }
}

// 我们需要一个 min_int 函数来辅助计算
fn min_int(a: Int, b: Int) -> Int {
  if a < b { a } else { b }
}
fn aggro_system(_backend: &@system.Backend) -> Unit {
  // 遍历所有单位 (不再只关心玩家)
  for unit_a in all_units.val {
    // 检查单位 a 是否空闲，并且获取它的阵营
    let is_idle = attack_targets.get(unit_a) is None && destinations.get(unit_a) is None
    if is_idle && teams.get(unit_a) is Some(team_a) {

      let mut closest_target = None
      let mut min_distance = 99999.0

      if @position.positions.get(unit_a) is Some(pos_a) {
        // 再次遍历所有单位，寻找一个不同阵营的目标
        for unit_b in all_units.val {
          if teams.get(unit_b) is Some(team_b) {

            // 【核心修正】只要阵营不同，就是潜在目标！
            if team_a != team_b {
              if @position.positions.get(unit_b) is Some(pos_b) {
                let distance = pos_a.0.distance_to(pos_b.0)

                if combat_stats.get(unit_a) is Some(stats) && 
                   distance < stats.aggro_range && 
                   distance < min_distance {

                  min_distance = distance
                  closest_target = Some(unit_b)
                }
              }
            }
          }
        }
      }

      if closest_target is Some(target) {
        println("[Log] Aggro System: Unit \{unit_a} (\{team_a}) auto-targeting \{target}")
        attack_targets.set(unit_a, target)
      }
    }
  }
}
// ---------------------------------
//  全新的定位系统 (融合了移动和避障)
// ---------------------------------
// ---------------------------------
//  全新的定位系统 (融合了移动和避障)
// ---------------------------------
fn positioning_system(_backend: &@system.Backend) -> Unit {
  // --- 阶段一：计算每个单位的“基础意图”速度 ---
  let base_velocities: Map[@system.Entity, @math.Vec2D] = Map::new()
  for entity in all_units.val {
    if destinations.get(entity) is Some(dest) {
      if @position.positions.get(entity) is Some(pos) {
        let distance = pos.0.distance_to(dest)
        if distance < 5.0 {
          destinations.remove(entity)
          base_velocities.set(entity, @math.Vec2D(0.0, 0.0))
        } else {
          let direction = (dest - pos.0).normalize()
          let speed = 2.0
          base_velocities.set(entity, direction.scalar_mul(speed))
        }
      }
    } else {
      base_velocities.set(entity, @math.Vec2D(0.0, 0.0))
    }
  }

  // --- 阶段二：计算每个单位受到的“避障推力” ---
 let avoidance_vectors: Map[@system.Entity, @math.Vec2D] = Map::new()
  for unit_a in all_units.val {
    let mut total_avoidance_vec = @math.Vec2D(0.0, 0.0)
    if @position.positions.get(unit_a) is Some(pos_a) && teams.get(unit_a) is Some(team_a) {
      if avoidance_behaviors.get(unit_a) is Some(behavior_a) {
        for unit_b in all_units.val {
          if unit_a != unit_b {
            if @position.positions.get(unit_b) is Some(pos_b) && teams.get(unit_b) is Some(team_b) {
              let distance = pos_a.0.distance_to(pos_b.0)
              if distance < behavior_a.avoidance_radius {
                let direction = (pos_a.0 - pos_b.0).normalize()
                let strength = (behavior_a.avoidance_radius - distance) / behavior_a.avoidance_radius
                let push_force = direction.scalar_mul(strength)

                // 【核心修正】判断是队友还是敌人
                if team_a != team_b {
                  // 是敌人，施加更大的推力
                  total_avoidance_vec = total_avoidance_vec + push_force.scalar_mul(ENEMY_PUSH_FACTOR)
                } else {
                  // 是队友，施加正常的推力
                  total_avoidance_vec = total_avoidance_vec + push_force
                }
              }
            }
          }
        }
      }
    }
    avoidance_vectors.set(unit_a, total_avoidance_vec)
  }

  // --- 【核心修正】阶段三：融合速度 ---
  for entity in all_units.val {
    // 使用 match 语句来安全地处理 Option 类型，如果 get 失败则提供默认值
    let base_vel = match base_velocities.get(entity) {
      Some(vel) => vel;
      None => @math.Vec2D(0.0, 0.0);
    }
    let avoid_vec = match avoidance_vectors.get(entity) {
      Some(vec) => vec;
      None => @math.Vec2D(0.0, 0.0);
    }
    
    // 现在 base_vel 和 avoid_vec 都是确定的 Vec2D 类型，可以安全地进行计算
    let final_vel = base_vel + avoid_vec.scalar_mul(AVOIDANCE_STRENGTH)
    @velocity.velocities.set(entity, final_vel)
  }
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
fn draw_drag_box_system(backend: &@system.Backend) -> Unit {
  if is_dragging.val {
    let start_pos = drag_start_pos.val
    let current_pos = @system.mouse.pos

    let camera_pos = @camera.get_position()
    let screen_start_pos = start_pos - camera_pos
    let screen_current_pos = current_pos - camera_pos

    // 修正：使用我们自己写的 min_double
    let x = min_double(screen_start_pos[X], screen_current_pos[X])
    let y = min_double(screen_start_pos[Y], screen_current_pos[Y])
    let width = (start_pos[X] - current_pos[X]).abs()
    let height = (start_pos[Y] - current_pos[Y]).abs()

    backend.draw_stroke_rect(x=x, y=y, width=width, height=height, color="cyan")
  }
}

const AVOIDANCE_STRENGTH: Double = 4

fn combat_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0

  // --- 阶段一：更新冷却 ---
  for unit in combat_stats.keys() {
    if combat_stats.get(unit) is Some(stats) {
      if stats.current_cooldown > 0.0 {
        let new_cooldown = stats.current_cooldown - delta_seconds
        combat_stats.set(unit, { ..stats, current_cooldown: new_cooldown })
      }
    }
  }

  // --- 阶段二：处理攻击 ---
  attack_targets.each(fn(attacker, target) {
    if target.is_alive() && healths.get(target) is Some(_) {
      if combat_stats.get(attacker) is Some(attacker_stats) && 
         @position.positions.get(attacker) is Some(attacker_pos) &&
         @position.positions.get(target) is Some(target_pos) {

        let distance = attacker_pos.0.distance_to(target_pos.0)
        if distance > attacker_stats.attack_range {
          destinations.set(attacker, target_pos.0)
        } else {
          destinations.remove(attacker)
          //@velocity.velocities.set(attacker, @math.Vec2D(0.0, 0.0))
          if attacker_stats.current_cooldown <= 0.0 {
            combat_stats.set(attacker, { ..attacker_stats, current_cooldown: attacker_stats.attack_cooldown })
            if healths.get(target) is Some(target_health) {
               let new_current_health = target_health.current - attacker_stats.attack_damage
               let new_health_component = { ..target_health, current: new_current_health }
               healths.set(target, new_health_component)
            }
          }
        }
      }
    } else {
      attack_targets.remove(attacker)
    }
  })

  // --- 阶段三：判定死亡单位，并将其加入“垃圾回收”列表 ---
  for unit in all_units.val {
    // 检查单位是否还“活着”（未被标记为destroy），并且血量已耗尽
    if unit.is_alive() {
      if healths.get(unit) is Some(health) && health.current <= 0.0 {
        // 只提交死亡名单，不做任何清理！
        entities_to_cleanup.val.push(unit)
        // 标记为死亡后，为了防止重复添加，可以先将其血量设为一个特殊值
        healths.set(unit, {..health, current: -1.0})
      }
    }
  }
}
// ---------------------------------
//  全新的清理系统
// ---------------------------------
fn cleanup_system(_backend: &@system.Backend) -> Unit {
  // 检查是否有需要清理的实体
  if entities_to_cleanup.val.length() > 0 {
    // 1. 执行我们之前编写的、最彻底的清理逻辑
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
    }

    // 2. 更新主逻辑列表，移除所有已清理的单位
    all_units.val = all_units.val.filter(fn(unit) {
      !entities_to_cleanup.val.contains(unit)
    })
    
    // 3. 清空垃圾回收列表，为下一帧做准备
    entities_to_cleanup.val.clear()
  }
}
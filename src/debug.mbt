let one_shot_effects: Set[@system.Entity] = Set::new()

// 【修正】去掉了 frame_count=

//测试动画系统
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


pub struct DynamicTransform {
  rotation_speed: Double // 每秒旋转的弧度
  scale_speed: Double    // 缩放脉冲的速度
  scale_amplitude: Double // 缩放脉冲的幅度 (e.g., 0.2 表示在 80% 到 120% 之间缩放)

  // 内部状态，用于动画计算
  _current_angle: Double
  _time_elapsed: Double
}

// 存储所有拥有此行为的实体
pub let dynamic_transforms: Map[@system.Entity, DynamicTransform] = Map::new()

// ---------------------------------
//  动态变换系统
// ---------------------------------
// ---------------------------------
//  动态变换系统 (最终修正版)
// ---------------------------------
// ---------------------------------
//  动态变换系统 (最终正确版)
// ---------------------------------
pub fn dynamic_transform_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0

  for entity in dynamic_transforms.keys() {
    if dynamic_transforms.get(entity) is Some(transform_data) {
      if entity.is_alive() {
        // 1. 更新内部动画状态
        let new_angle = transform_data._current_angle + transform_data.rotation_speed * delta_seconds
        let new_time = transform_data._time_elapsed + delta_seconds
        
        let updated_transform_data = {
            ..transform_data,
            _current_angle: new_angle,
            _time_elapsed: new_time,
        }

        // 2. 计算当前的缩放值
        let scale_pulse = @kmath.sin(new_time * transform_data.scale_speed)
        let current_scale = 1.0 + scale_pulse * transform_data.scale_amplitude
        
        // 3. 【核心修正】直接获取【可变的】Sprite 组件并修改它！
        if @sprite.sprites.get(entity) is Some(sprite) {
          
          // a. 创建独立的缩放和旋转变换
          let scale_transform = @math.Transform::from_scale(current_scale, current_scale)
          let rotation_transform = @math.Transform::from_rotation_rad(new_angle)
          
          // b. 将它们相乘得到最终的变换矩阵
          let final_transform = rotation_transform * scale_transform
          println("[Log  DynamicTransform]: Entity \{entity}, New Angle: \{new_angle}, Transform A: \{final_transform.a}")
          // c. 【核心】直接修改 Sprite 的 transform 字段！
          sprite.transform = final_transform
        }
        
        // 4. 将更新后的内部状态写回
        dynamic_transforms.set(entity, updated_transform_data)
      }
    }
  }
}
/// 更新一个单位的 Sprite，使其朝向指定的方向向量
pub fn unit_orientation_system(_backend: &@system.Backend) -> Unit {
  for unit in all_units.val {
    if unit.is_alive() {
      let mut new_direction: Option[@math.Vec2D] = None

      if attack_targets.get(unit) is Some(target) {
        if @position.positions.get(unit) is Some(unit_pos) &&
           @position.positions.get(target) is Some(target_pos) {
          
          let direction_vec = target_pos.0 - unit_pos.0
          if direction_vec.distance_to(@math.Vec2D::zero()) > 1.0 {
            new_direction = Some(direction_vec.normalize())
          }
        }
      } else if player_head.val != Some(unit) { // 火车头由 player_control_system 控制朝向
        if @velocity.velocities.get(unit) is Some(vel) {
          if vel.0.distance_to(@math.Vec2D::zero()) > 0.1 {
            new_direction = Some(vel.0.normalize())
          }
        }
      }

      if new_direction is Some(dir) {
        update_unit_orientation(unit, dir)
      }
    }
  }
}

// ---------------------------------
//  渲染辅助函数 (最终修正版)
// ---------------------------------
/// 更新一个单位的 Sprite，使其朝向指定的方向向量
pub fn update_unit_orientation(entity: @system.Entity, direction: @math.Vec2D) -> Unit {
  if @sprite.sprites.get(entity) is Some(sprite) {
    // 1. 从朝向向量计算出【目标旋转角度】
    let target_angle = @kmath.atan2(direction[Y], direction[X])
    
    let base_rotation = sprite.transform.get_rotation_rad()

    let angle_to_apply = target_angle - base_rotation

    sprite.transform = sprite.transform * @math.Transform::from_rotation_rad(angle_to_apply)
    
  }
}
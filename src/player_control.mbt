let player_head: Ref[Option[@system.Entity]] = Ref::new(None)
// 新增：玩家的加速度，数值越大，起步越快
let player_facing_vector: Ref[@math.Vec2D] = Ref::new(@math.Vec2D(0.0, -1.0))

const PLAYER_SPEED: Double = 3.0 // 这个保留，现在是坦克的固定前进速度

// 【新增】玩家的转向速度（单位：弧度/秒）
const PLAYER_TURN_SPEED: Double = 4.0 


let player_tail: Ref[Option[@system.Entity]] = Ref::new(None)

struct PathHistory {
  points: Array[@math.Vec2D]
}
let path_histories: Map[@system.Entity, PathHistory] = Map::new()

// 为了防止内存无限增长，每个单位最多只保留最近的500个路径点
const MAX_HISTORY_LENGTH: Int = 500

// 新增：“车厢”组件
struct TrainCar {
  prev: Option[@system.Entity] // 前面的单位
  next: Option[@system.Entity] // 后面的单位
}
// 新增：存储所有车厢的 Map
let train_cars: Map[@system.Entity, TrainCar] = Map::new()

// 新增：“小火车”车厢之间的理想间距
const TRAIN_SPACING: Double = 40.0
pub fn player_control_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0
  if player_head.val is Some(head_entity) {

    let mut turn_input = 0.0 // -1.0 代表向左转, 1.0 代表向右转

    // 1. 读取转向输入
    if @system.is_pressed(@system.KeyA) || @system.is_pressed(@system.ArrowLeft) {
      turn_input = -1.0
    }
    if @system.is_pressed(@system.KeyD) || @system.is_pressed(@system.ArrowRight) {
      turn_input = 1.0
    }

    // 2. 如果有转向输入，就更新“朝向向量”
    if turn_input != 0.0 {
      let turn_angle = PLAYER_TURN_SPEED * turn_input * delta_seconds
      // 调用我们之前写的 rotate_vec2d 辅助函数来旋转向量
      player_facing_vector.val = rotate_vec2d(player_facing_vector.val, turn_angle)
    }

    // 3. 最终速度永远是“朝向”乘以“固定速度”
    // 我们不再需要检查 W/S 键，实现了自动前进！
    let final_velocity = player_facing_vector.val.normalize().scalar_mul(PLAYER_SPEED)
    @velocity.velocities.set(head_entity, final_velocity)


  }
}

pub fn player_train_management_system(_backend: &@system.Backend) -> Unit {
  for unit, team in teams {
    if team == Team::Player {
      let is_in_train = player_head.val == Some(unit) || train_cars.get(unit) is Some(_)

      if !is_in_train {
        if player_head.val is None {
          player_head.val = Some(unit)
          player_tail.val = Some(unit)
          train_cars.set(unit, { prev: None, next: None })
          println("[Log] Train Manager: Head created -> \{unit}")
        } else {
          let current_tail_entity = player_tail.val.unwrap()

          // 【核心修正】使用“取出-修改副本-写回”模式
          if train_cars.get(current_tail_entity) is Some(tail_car_component) {
            // 1. 创建一个旧车尾组件的修改后副本
            let updated_tail_component = { ..tail_car_component, next: Some(unit) }
            // 2. 将这个全新的副本写回
            train_cars.set(current_tail_entity, updated_tail_component)
          }

          train_cars.set(unit, { prev: Some(current_tail_entity), next: None })
          player_tail.val = Some(unit)
          println("[Log] Train Manager: New car attached -> \{unit}")
        }
      }
    }
  }
}



// ---------------------------------
//  路径记录系统
// ---------------------------------
// ---------------------------------
//  轨迹录制系统 (为每个单位录制)
// ---------------------------------
fn path_history_system(_backend: &@system.Backend) -> Unit {
  // 遍历所有拥有“历史记录”能力的单位
  for unit in path_histories.keys() {
    if path_histories.get(unit) is Some(history) {
      if @position.positions.get(unit) is Some(pos) {
        // 将当前位置添加到历史记录的末尾
        history.points.push(pos.0)

        // 如果历史记录太长，就移除最旧的那个点
        if history.points.length() > MAX_HISTORY_LENGTH {
          let _ = history.points.remove(0)
        }
        // 将更新后的 history 写回
        path_histories.set(unit, history)
      }
    }
  }
}

pub fn train_snake_follow_system(_backend: &@system.Backend) -> Unit {
  // 从第一节车厢开始，遍历整个火车链条
  let mut current_car_opt: Option[@system.Entity] = None
  if player_head.val is Some(h) {
    if train_cars.get(h) is Some(head_data) {
      current_car_opt = head_data.next
    }
  }

  // 追踪我们正在为第几节车厢计算位置 (第一节是1，第二节是2...)
  let mut car_index = 1

  while current_car_opt is Some(car_entity) {
    if train_cars.get(car_entity) is Some(car_data) && car_data.prev is Some(leader) {
      if path_histories.get(leader) is Some(leader_history) {
        let path = leader_history.points
        if path.length() < 1 { continue }

        // 【核心】这节车厢的目标，是离火车头 (不是它的直接领袖) car_index * TRAIN_SPACING 的距离
        let desired_distance_from_head = car_index.to_double() * TRAIN_SPACING
        
        // 沿着【火车头】的轨迹，向回搜索那个精确的点
        let head_path_opt = if player_head.val is Some(h) { path_histories.get(h) } else { None }
        if head_path_opt is Some(head_history) {
            let head_path = head_history.points
            if head_path.length() > 1 {
                let mut target_pos = head_path[head_path.length() - 1]
                let mut distance_travelled_backwards = 0.0

                for i = head_path.length() - 2; i >= 0; i = i - 1 {
                    let p_new = head_path[i + 1]
                    let p_old = head_path[i]
                    let segment_length = p_new.distance_to(p_old)

                    if (distance_travelled_backwards + segment_length) >= desired_distance_from_head {
                        let distance_needed_on_this_segment = desired_distance_from_head - distance_travelled_backwards
                        
                        // 【核心修正】使用我们自己的 vec2d_lerp 函数
                        let ratio = if segment_length == 0.0 { 0.0 } else { distance_needed_on_this_segment / segment_length }
                        target_pos = vec2d_lerp(p_new, p_old, ratio)
                        break
                    }
                    distance_travelled_backwards += segment_length
                }
                
                // 【核心】直接将车厢的位置“瞬移”到计算出的目标点
                @position.positions.set(car_entity, target_pos)
            }
        }
      }
    }
    
    // 移动到链表的下一个节点
    car_index += 1
    if train_cars.get(car_entity) is Some(car_data) {
      current_car_opt = car_data.next
    } else {
      current_car_opt = None
    }
  }
}

// ---------------------------------
//  辅助函数：处理小火车断链重连
// ---------------------------------
fn relink_train_chain(dead_unit: @system.Entity) -> Unit {
  // 1. 检查死亡单位是否是火车的一部分
  if train_cars.get(dead_unit) is Some(dead_car_data) {
    let prev_entity_opt = dead_car_data.prev
    let next_entity_opt = dead_car_data.next
    
    // 2. "接骨手术"：当一个【中间】车厢死亡时
    if prev_entity_opt is Some(prev_entity) && next_entity_opt is Some(next_entity) {
      // a. 更新前面车厢的 next 指针
      if train_cars.get(prev_entity) is Some(prev_car_component) {
        let updated_prev_component = { ..prev_car_component, next: Some(next_entity) }
        train_cars.set(prev_entity, updated_prev_component)
      }
      // b. 更新后面车厢的 prev 指针
      if train_cars.get(next_entity) is Some(next_car_component) {
        let updated_next_component = { ..next_car_component, prev: Some(prev_entity) }
        train_cars.set(next_entity, updated_next_component)
      }
      println("[Log] Relinked train chain between \{prev_entity} and \{next_entity}")
    }
    
    // 3. 处理边界情况：车头或车尾死亡
    if player_head.val == Some(dead_unit) { // 车头死了
      player_head.val = next_entity_opt // 新车头是它的下一个 (可能是None)
      // 如果新车头存在，清除它的 prev 指针
      if next_entity_opt is Some(new_head) {
        if train_cars.get(new_head) is Some(new_head_comp) {
          train_cars.set(new_head, {..new_head_comp, prev: None})
        }
      }
    }
    if player_tail.val == Some(dead_unit) { // 车尾死了
      player_tail.val = prev_entity_opt // 新车尾是它的上一个 (可能是None)
      // 如果新车尾存在，清除它的 next 指针
      if prev_entity_opt is Some(new_tail) {
        if train_cars.get(new_tail) is Some(new_tail_comp) {
          train_cars.set(new_tail, {..new_tail_comp, next: None})
        }
      }
    }
  }
}

fn _connect_player_unit_to_train(new_unit: @system.Entity, team: Team) -> Unit {
  // 1. 将单位添加到全局单位列表中
  all_units.val.push(new_unit)

  // 2. 检查单位阵营
  if team == Team::Player {
    // a. 为这个单位创建“轨迹历史”组件，让它能被其他车厢跟随
    path_histories.set(new_unit, { points: [] })

    // b. 将这个单位连接到小火车的双向链表上
    if player_head.val is None {
      // 如果还没有火车头，这个单位就成为火车头
      player_head.val = Some(new_unit)
      player_tail.val = Some(new_unit)
      train_cars.set(new_unit, { prev: None, next: None })
    } else {
      // 如果已经有火车了，就将这个单位作为新车厢连接到车尾
      let current_tail_entity = player_tail.val.unwrap()
      if train_cars.get(current_tail_entity) is Some(tail_car_comp) {
        let updated_comp = { ..tail_car_comp, next: Some(new_unit) }
        train_cars.set(current_tail_entity, updated_comp)
      }
      train_cars.set(new_unit, { prev: Some(current_tail_entity), next: None })
      player_tail.val = Some(new_unit)
    }
  }
}

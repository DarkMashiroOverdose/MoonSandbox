let player_head: Ref[Option[@system.Entity]] = Ref::new(None)
// 新增：玩家的加速度，数值越大，起步越快
const PLAYER_ACCELERATION: Double = 0.5

// 新增：摩擦力系数，数值越接近1，惯性越大；越接近0，刹车越快
const PLAYER_FRICTION: Double = 0.5

const PLAYER_SPEED: Double = 3
let player_tail: Ref[Option[@system.Entity]] = Ref::new(None)

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
  if player_head.val is Some(head_entity) {
    
    // 1. 获取单位当前的“速度向量(Vec2D)”
    let current_velocity_vec2d = match @velocity.velocities.get(head_entity) {
      // 【修正 #1】移除了分支末尾多余的逗号
      Some(vel_component) => vel_component.0
      None => @math.Vec2D(0.0, 0.0)
    }

    // 2. 获取玩家的输入方向
    let direction = @system.key_vector(
        @system.KeyW, 
        @system.KeyS, 
        @system.KeyA, 
        @system.KeyD)

    let mut new_velocity_vec2d = current_velocity_vec2d
    
    // 3. 【修正 #2】使用 distance_to(@math.Vec2D::zero()) 代替 magnitude()
    if direction.distance_to(@math.Vec2D::zero()) > 0.0 {
      // 如果有按键输入：施加加速度
      let acceleration_vec = direction.normalize().scalar_mul(PLAYER_ACCELERATION)
      new_velocity_vec2d = current_velocity_vec2d + acceleration_vec
    } else {
      // 如果没有按键输入：施加摩擦力
      new_velocity_vec2d = current_velocity_vec2d.scalar_mul(PLAYER_FRICTION)
    }

    // 4. 【修正 #2】使用 distance_to(@math.Vec2D::zero()) 代替 magnitude()
    if new_velocity_vec2d.distance_to(@math.Vec2D::zero()) > PLAYER_SPEED {
      new_velocity_vec2d = new_velocity_vec2d.normalize().scalar_mul(PLAYER_SPEED)
    }

    // 5. 将最终计算出的 Vec2D 速度，应用回单位
    @velocity.velocities.set(head_entity, new_velocity_vec2d)
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
fn train_follow_system(_backend: &@system.Backend) -> Unit {
  for car, train_data in train_cars {
    // 【核心修正】从 prev 字段获取领头者
    if train_data.prev is Some(leader) {
      if car.is_alive() && leader.is_alive() {
        if @position.positions.get(car) is Some(car_pos) && 
           @position.positions.get(leader) is Some(leader_pos) {
          
          let distance = car_pos.0.distance_to(leader_pos.0)
          if distance > TRAIN_SPACING {
            destinations.set(car, leader_pos.0)
          }
        }
      }
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
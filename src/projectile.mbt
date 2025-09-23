// ---------------------------------
// 抛射物 & Debuff 相关定义
// ---------------------------------

/// 抛射物的命中效果
//pub enum ProjectileEffect {
//  SingleTarget(Double)
//  AreaOfEffect(Double, Double)
//  ApplyDebuff(DebuffType, Double)
//  CreateHazardousArea(Double, Double, Double)
//} derive(Show)

/// 抛射物组件，描述了一个飞行中的子弹
struct Projectile {
  source: @system.Entity 
  source_team: Team // 发射者的队伍
  target: @system.Entity
  speed: Double
  on_hit_effects: Array[OnHitEffect]
  max_turn_rate: Double // 每秒最大转向角度（单位：弧度）
  navigation_constant: Double // 比例导引常数 N
  on_hit_vfx: VFX_Type    // 【新增】视觉效果
  area_effect_vfx: Option[VFX_Type]    // 【新增】视觉效果
}

// --- 全局 Map ---
// 存储所有飞行中的抛射物
let projectiles: Map[@system.Entity, Projectile] = Map::new()
// 存储所有单位当前激活的 Debuff
const PROJECTILE_HIT_THRESHOLD: Double = 5.0 // 命中判定距离

/// 全新函数：专门处理子弹攻击的执行逻辑
fn execute_bullet_attack(attacker: @system.Entity, target: @system.Entity, stats: CombatStats) -> Unit {
  println("[Log] Executing Bullet Attack from \{attacker} to \{target}")
  
  if teams.get(attacker) is Some(attacker_team) {
    let bullet_sprite = @sprite.Sprite::from_shape(
        @sprite.ColoredShape::new(@sprite.Shape::circle(5.0), @sprite.DrawStyle::fill("red")),
        200, 
        layer=@sprite.RenderLayer::game_world(),
    )

    spawn_projectile(
      attacker,
      target,
      attacker_team,
      stats.on_hit_effects,
      5.0, 
      bullet_sprite,
      stats.on_hit_vfx,
      stats.area_effect_vfx,
    )
  }
}

fn spawn_projectile(
  source: @system.Entity,
  target: @system.Entity,
  source_team: Team,
  effects: Array[OnHitEffect], 
  speed: Double,
  sprite: @sprite.Sprite,
  on_hit_vfx: VFX_Type,
  area_effect_vfx: Option[VFX_Type]
) -> Unit {
  if @position.positions.get(source) is Some(source_pos) &&
     @position.positions.get(target) is Some(target_pos) {
    let projectile_entity = @system.Entity::new()

    @position.positions.set(projectile_entity, source_pos.0)
    @sprite.sprites.set(projectile_entity, sprite)
    projectiles.set(projectile_entity, {
      source: source,
      source_team: source_team,
      target: target,
      speed: speed,
      on_hit_effects: effects,
      max_turn_rate: 0.5,
      navigation_constant: 1.5,
      on_hit_vfx: on_hit_vfx,
      area_effect_vfx: area_effect_vfx
    })
    let initial_direction = (target_pos.0 - source_pos.0).normalize()
    @velocity.velocities.set(projectile_entity, initial_direction.scalar_mul(speed))
  }
}
pub fn projectile_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0

  let current_projectiles_snapshot = projectiles.keys()

  for bullet in current_projectiles_snapshot {
    if projectiles.get(bullet) is Some(proj_data) {
      guard bullet.is_alive() else { continue }
      
      if @position.positions.get(bullet) is Some(bullet_pos) &&
         @velocity.velocities.get(bullet) is Some(bullet_vel) {

        // --- 1. 制导逻辑：动态寻找最近的目标进行追踪 ---
        let mut closest_target_for_guidance = None
        let mut min_guidance_distance = 99999.0
        for unit in all_units.val {
          if teams.get(unit) is Some(unit_team) && unit_team != proj_data.source_team {
            if @position.positions.get(unit) is Some(unit_pos) {
              let distance = bullet_pos.0.distance_to(unit_pos.0)
              if distance < min_guidance_distance {
                min_guidance_distance = distance
                closest_target_for_guidance = Some(unit)
              }
            }
          }
        }

        // 如果找到了制导目标，就更新飞行方向
        if closest_target_for_guidance is Some(target) && @position.positions.get(target) is Some(target_pos) {
          let line_of_sight = target_pos.0 - bullet_pos.0
          let los_rate = signed_angle_between(bullet_vel.0, line_of_sight)
          let desired_turn_speed = proj_data.navigation_constant * los_rate
          let max_turn_this_frame = proj_data.max_turn_rate * delta_seconds
          let actual_turn_angle = @kmath.clamp(desired_turn_speed, -max_turn_this_frame, max_turn_this_frame)
          let new_velocity_direction = rotate_vec2d(bullet_vel.0, actual_turn_angle).normalize()
          let final_velocity = new_velocity_direction.scalar_mul(proj_data.speed)
          @velocity.velocities.set(bullet, final_velocity)
        }
        
        // --- 2. 【核心改造】碰撞逻辑：检查是否撞到了“任何”一个敌人 ---
        let mut hit_target = None
        for unit in all_units.val {
            if teams.get(unit) is Some(unit_team) && unit_team != proj_data.source_team {
                if @position.positions.get(unit) is Some(unit_pos) {
                    // 简单的碰撞检测：距离小于单位半径 (例如 32.0)
                    if bullet_pos.0.distance_to(unit_pos.0) < 32.0 {
                        hit_target = Some(unit)
                        break // 只要撞到一个，就停止检查
                    }
                }
            }
        }

        // --- 3. 命中处理 ---
        if hit_target is Some(actual_hit_target) {
          // 从系统中移除子弹
          projectiles.remove(bullet)
          entities_to_cleanup.val.push(bullet)

          // 对【实际撞到的目标】应用效果
          if @position.positions.get(actual_hit_target) is Some(hit_pos) {
            apply_projectile_effect(proj_data, actual_hit_target, hit_pos.0)
            
          }
        }
      }
    }
  }
}
fn apply_projectile_effect(proj_data: Projectile, actual_hit_target: @system.Entity, hit_pos: @math.Vec2D) -> Unit {
  println("[Log - VFX Request] An on-hit VFX of type '\{proj_data.on_hit_vfx}' was requested.")
  vfx_requests.val.push({
    vfx_type: proj_data.on_hit_vfx,
    position: hit_pos,
    rotation: 0.0,
  })
  apply_all_effects(proj_data.source, actual_hit_target, proj_data.on_hit_effects)
}

pub struct HazardousArea {
  source: @system.Entity
  source_team: Team 
  on_tick_effects: Array[OnHitEffect] // << 用这个替换掉 damage_per_second
  radius: Double
  remaining_duration: Double
  tick_timer: Double
}

pub let hazardous_areas: Map[@system.Entity, HazardousArea] = Map::new()

fn spawn_hazardous_area(
    source: @system.Entity,
    pos: @math.Vec2D, 
    radius: Double, 
    duration: Double, 
    team: Team, 
    vfx_type_opt: Option[VFX_Type],
    tick_effects: Array[OnHitEffect] // << 参数更新
) -> Unit {
  println("[Log Spawning] Spawning hazardous area at (\{pos[X]}, \{pos[Y]})")
  let area_entity = @system.Entity::new()
  @position.positions.set(area_entity, pos)

  if vfx_type_opt is Some(vfx_type) {
    vfx_requests.val.push({
      vfx_type: vfx_type,
      position: pos,
      rotation: 0.0,
    })
  }

  // 使用更新后的 HazardousArea 结构体
  hazardous_areas.set(area_entity, {
    source: source,
    source_team: team,
    on_tick_effects: tick_effects, // << 把收到的效果列表存进去
    radius: radius,
    remaining_duration: duration,
    tick_timer: 1.0, 
  })
}
pub fn hazardous_area_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0
  
  for area_entity in hazardous_areas.keys() {
    if hazardous_areas.get(area_entity) is Some(area_data) {
      
      let new_duration = area_data.remaining_duration - delta_seconds
      let new_tick_timer = area_data.tick_timer - delta_seconds
      
      if new_duration <= 0.0 {
        entities_to_cleanup.val.push(area_entity)
        hazardous_areas.remove(area_entity)
        continue
      }

      if new_tick_timer <= 0.0 {
        if @position.positions.get(area_entity) is Some(area_pos) {
          apply_effects_in_area(
            area_data.source,
            area_pos.0,
            area_data.radius,
            area_data.on_tick_effects, // << 核心：传递区域自带的“效果工具箱”
            area_data.source_team
          )
        }
        let final_updated_data = {
          ..area_data,
          remaining_duration: new_duration,
          tick_timer: 1.0,
        }
        hazardous_areas.set(area_entity, final_updated_data)

      } else {
        let final_updated_data = {
          ..area_data,
          remaining_duration: new_duration,
          tick_timer: new_tick_timer,
        }
        hazardous_areas.set(area_entity, final_updated_data)
      }
    }
  }
}
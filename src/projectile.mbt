// ---------------------------------
// 抛射物 & Debuff 相关定义
// ---------------------------------

/// 定义 Debuff 的具体类型
enum DebuffType {
  Slow(Double) // factor: 速度乘数, e.g., 0.5 代表减速50%
  // 未来可以扩展: Poison(damage_per_sec: Double), Stun, ...
} derive(Eq, Show)

/// 附加在单位身上的 Debuff 组件
struct Debuff {
  kind: DebuffType
  remaining_duration: Double
}

/// 抛射物的命中效果
/// 抛射物的命中效果
enum ProjectileEffect {
  SingleTarget(Double)            // 包含一个 Double 类型的伤害值
  AreaOfEffect(Double, Double)    // 包含伤害值(Double)和半径(Double)
  ApplyDebuff(DebuffType, Double) // 包含 Debuff 类型和持续时间(Double)
} derive(Show)
/// 抛射物组件，描述了一个飞行中的子弹
struct Projectile {
  source_team: Team // 发射者的队伍
  target: @system.Entity
  speed: Double
  effect: ProjectileEffect

  max_turn_rate: Double // 每秒最大转向角度（单位：弧度）
  navigation_constant: Double // 比例导引常数 N
}

// --- 全局 Map ---
// 存储所有飞行中的抛射物
let projectiles: Map[@system.Entity, Projectile] = Map::new()
// 存储所有单位当前激活的 Debuff
let active_debuffs: Map[@system.Entity, Array[Debuff]] = Map::new()

const PROJECTILE_HIT_THRESHOLD: Double = 5.0 // 命中判定距离

/// 全新函数：专门处理子弹攻击的执行逻辑
fn execute_bullet_attack(attacker: @system.Entity, target: @system.Entity, stats: CombatStats) -> Unit {
  println("[Log] Executing Bullet Attack from \{attacker} to \{target}")
  
  // 安全地获取攻击者的阵营信息
  if teams.get(attacker) is Some(attacker_team) {
    // 1. 定义子弹的命中效果
    //    这里可以根据 stats 或者其他逻辑变得更复杂
    let effect = ProjectileEffect::AreaOfEffect(stats.attack_damage,100.0)

    // 2. 定义子弹的视觉外观
    //    未来可以根据单位类型或武器类型改变外观
    let bullet_sprite = @sprite.Sprite::from_shape(
        @sprite.ColoredShape::new(@sprite.Shape::circle(5.0), @sprite.DrawStyle::fill("red")),
        200, // z-index
        layer=@sprite.RenderLayer::game_world(),
    )

    // 3. 调用“军工厂”函数，传入所有配置好的参数
    spawn_projectile(
      attacker,
      target,
      attacker_team,
      effect,
      5.0, // 子弹飞行速度, 未来也可以放入 CombatStats
      bullet_sprite
    )
  }
}

fn spawn_projectile(
  source: @system.Entity,
  target: @system.Entity,
  source_team: Team,
  effect: ProjectileEffect,
  speed: Double,
  sprite: @sprite.Sprite, // 直接传递配置好的 Sprite
) -> Unit {
  if @position.positions.get(source) is Some(source_pos) &&
     @position.positions.get(target) is Some(target_pos){
    let projectile_entity = @system.Entity::new()

    // 1. 设置初始位置、Sprite 和抛射物组件
    @position.positions.set(projectile_entity, source_pos.0)
    @sprite.sprites.set(projectile_entity, sprite)
    projectiles.set(projectile_entity, {
      source_team: source_team,
      target: target,
      speed: speed,
      effect: effect,
      max_turn_rate: 0.5, // 每秒最多转 π 弧度 (180度)
      navigation_constant: 1.5, // 一个比较灵敏的制导系数
    })
    let initial_direction = (target_pos.0 - source_pos.0).normalize()
    @velocity.velocities.set(projectile_entity, initial_direction.scalar_mul(speed))
    // 2. 注意：这里【不】设置速度(velocity)！
    // 速度的计算和更新由 projectile_system 每帧动态处理，以确保始终飞向目标。
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
            apply_projectile_effect(proj_data, hit_pos.0)
             ///////////////////临时测试爆炸效果///////////////////
          // 1. 创建一个新的、临时的实体用于播放特效
          let effect_entity = @system.Entity::new()

          // 2. 将特效实体的初始位置设置在被攻击的目标身上
          @position.positions.set(effect_entity, bullet_pos.0.add(@math.Vec2D(185.0 / -2, 150.0/-2))) // 稍微往上偏移一点

          // 3. 在这个新实体上播放我们准备好的、不循环的爆炸动画
          @sprite.play_animation(
            effect_entity,
            explosion_animation,
            layer=@sprite.RenderLayer::game_world(),
          )

          // 2. 手动获取并更新 Sprite 的 zindex
          if @sprite.sprites.get(effect_entity) is Some(sprite) {
            let updated_sprite = { ..sprite, zindex: 500 }
            @sprite.sprites.set(effect_entity, updated_sprite)
          }
          one_shot_effects.add(effect_entity)
          ///////////////////临时测试爆炸效果///////////////////
          }
        }
      }
    }
  }
}
fn apply_projectile_effect(proj_data: Projectile, hit_pos: @math.Vec2D) -> Unit {
  match proj_data.effect {
    SingleTarget(damage) => {
      // 委托给“单体伤害”函数
      effect_apply_single_target_damage(proj_data.target, damage)
    }
    AreaOfEffect(damage, radius) => {
      // 委托给“范围伤害”函数
      effect_apply_aoe_damage(hit_pos, radius, damage, proj_data.source_team)
    }
    ApplyDebuff(effect, duration) => {
      // 委托给“施加Debuff”函数
      effect_apply_debuff(proj_data.target, effect, duration)
    }
  }
}


fn apply_debuff(target: @system.Entity, effect: DebuffType, duration: Double) -> Unit {
  let new_debuff = { kind: effect, remaining_duration: duration }
  if active_debuffs.get(target) is Some(existing_debuffs) {
    let new_debuffs = existing_debuffs
    new_debuffs.push(new_debuff)
    active_debuffs.set(target, new_debuffs)
  } else {
    active_debuffs.set(target, [new_debuff])
  }
}
//占位符debuff系统
fn debuff_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0
  active_debuffs.each(fn(unit, debuffs) {
    // 过滤掉已过期的 Debuff，只保留剩余时间 > 0 的
    let updated_debuffs = debuffs.filter_map(fn(debuff) {
      let new_duration = debuff.remaining_duration - delta_seconds
      if new_duration > 0.0 {
        Some({ ..debuff, remaining_duration: new_duration })
      } else {
        None // 返回 None 会被 filter_map 自动过滤掉
      }
    })

    if updated_debuffs.length() == 0 {
      active_debuffs.remove(unit) // 如果没有 Debuff 了，直接从 Map 中移除
    } else {
      active_debuffs.set(unit, updated_debuffs)
    }
  })
}
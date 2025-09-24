/// ------------------------
/// 战斗与寻敌系统
/// ------------------------
// 用 Map 存储拥有该组件的实体
let combat_stats: Map[@system.Entity, CombatStats] = Map::new()

// 新增：用于存储“谁正在攻击谁”的 Map
// Key: 攻击者, Value: 被攻击的目标
let attack_targets: Map[@system.Entity, @system.Entity] = Map::new()

pub struct CombatStats {
  attack_range: Double
  on_hit_effects: Array[OnHitEffect]
  attack_cooldown: Double
  current_cooldown: Double
  aggro_range: Double
  attack_type: AttackType
  aoe_radius: Double
  crit_rate: Double
  on_hit_vfx: VFX_Type 
  area_effect_vfx: Option[VFX_Type] 
}

pub enum AttackType {
  Melee   // 近战
  Bullet  // 子弹攻击
  Ranged  // 长距离直接攻击
  AoE     // 近战范围伤害
} derive(Show)
fn combat_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0

  // 攻击冷却循环
  for unit in combat_stats.keys() {
    if combat_stats.get(unit) is Some(stats) {
      if stats.current_cooldown > 0.0 {
        let new_cooldown = stats.current_cooldown - delta_seconds
        combat_stats.set(unit, { ..stats, current_cooldown: new_cooldown })
      }
    }
  }

  //选择攻击对象和执行攻击
  attack_targets.each(fn(attacker, target) {
    if target.is_alive() && healths.get(target) is Some(_) {
      if get_computed_stats(attacker) is Some(attacker_stats) && 
       @position.positions.get(attacker) is Some(attacker_pos) &&
       @position.positions.get(target) is Some(target_pos) {

        let distance = attacker_pos.0.distance_to(target_pos.0)
        if distance > attacker_stats.attack_range {
          destinations.set(attacker, target_pos.0)
        } else {
          destinations.remove(attacker)

          if attacker_stats.current_cooldown <= 0.0 {
            // 重置冷却
            combat_stats.set(attacker, { ..attacker_stats, current_cooldown: attacker_stats.attack_cooldown })

            //根据攻击类型进行调度
            match attacker_stats.attack_type {
              AttackType::Melee => {
                execute_melee_attack(attacker, target, attacker_stats)
              }
              AttackType::Bullet => {
                execute_bullet_attack(attacker, target, attacker_stats)
              }
              AttackType::Ranged => {
                //TODO: 实现远程瞬间伤害逻辑
                execute_bullet_attack(attacker, target, attacker_stats)
                println("[Log] Ranged Attack not implemented yet.")
              }
              AttackType::AoE => {
                execute_aoe_melee_attack(attacker, attacker_stats)
                println("[Log] AoE Attack not implemented yet.")
              }
            }
          }
        }
      }
    } else {
      attack_targets.remove(attacker)
    }
  })

  // 处理死亡单位
  for unit in all_units.val {
    if unit.is_alive() {
      if healths.get(unit) is Some(health) && health.current <= 0.0 {
        // 将死亡单位加入待清理列表，交由 cleanup_system 处理。
        entities_to_cleanup.val.push(unit)
        // 将血量设为-1，防止下一帧被重复添加。
        healths.set(unit, {..health, current: -1.0})
      }
    }
  }
}

fn aggro_system(_backend: &@system.Backend) -> Unit {
  for unit_a in all_units.val {
    // 检查单位 a 是否还活着，并获取它的阵营
    if unit_a.is_alive() && teams.get(unit_a) is Some(team_a) {
      
      // 【核心修正】根据阵营，执行不同的索敌逻辑
      if team_a == Team::Player {
        // --- 玩家单位的索敌逻辑 ---
        // 玩家单位（车头和车厢）只要没有当前目标，就应该立刻寻找新目标，无论是否在移动
        if attack_targets.get(unit_a) is None {
          let mut closest_target = None
          let mut min_distance = 99999.0

          if @position.positions.get(unit_a) is Some(pos_a) {
            for unit_b in all_units.val {
              if teams.get(unit_b) is Some(Team::Enemy) {
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
          if closest_target is Some(target) {
            attack_targets.set(unit_a, target)
          }
        }
      } else if team_a == Team::Enemy {
        // --- 敌人单位的索敌逻辑 (保持原样) ---
        // 敌人只有在空闲时才会寻找新目标
        let is_idle = attack_targets.get(unit_a) is None && destinations.get(unit_a) is None
        if is_idle {
          let mut closest_target = None
          let mut min_distance = 99999.0
          // ... (这部分寻找最近目标的逻辑和上面玩家的完全一样) ...
          if @position.positions.get(unit_a) is Some(pos_a) {
             for unit_b in all_units.val {
                if teams.get(unit_b) is Some(Team::Player) {
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
          if closest_target is Some(target) {
            attack_targets.set(unit_a, target)
          }
        }
      }
    }
  }
}

fn apply_all_effects(source: @system.Entity, target: @system.Entity, effects: Array[OnHitEffect]) -> Unit {
  for effect in effects {
    match effect {
      DealDamage(damage, vfx_opt) => {
        // 调用我们现有的伤害函数
        apply_damage(source, target, damage)
        if vfx_opt is Some(vfx_type) {
          if @position.positions.get(target) is Some(target_pos) {
            // 3. 发出 VFX 播放请求
            vfx_requests.val.push({
              vfx_type: vfx_type,
              position: target_pos.0,
              rotation: 0.0,
            })
          }
        }
      }
      ApplyBuff(buff_type, duration, vfx_opt) => {
        // 调用我们现有的 Buff 添加函数
        add_buff(target, buff_type, duration)
        if vfx_opt is Some(vfx_type) {
          if @position.positions.get(target) is Some(target_pos) {
            // 3. 发出 VFX 播放请求
            vfx_requests.val.push({
              vfx_type: vfx_type,
              position: target_pos.0,
              rotation: 0.0,
            })
          }
        }
      }
      CreateHazardousArea(tick_effects, radius, duration, vfx_opt) => {
        if @position.positions.get(target) is Some(target_pos) && teams.get(source) is Some(source_team) {
            spawn_hazardous_area(
                source, 
                target_pos.0, 
                radius, 
                duration, 
                source_team, 
                vfx_opt, // 传递VFX信息
                tick_effects // 传递效果列表
            )
        }
      }
      // ... 未来在这里扩展 ...
    }
  }
}

fn execute_aoe_melee_attack(attacker: @system.Entity, stats: CombatStats) -> Unit {
  if @position.positions.get(attacker) is Some(attacker_pos) && teams.get(attacker) is Some(attacker_team) {
    println("[Log] Executing AoE Melee Attack from \{attacker}")
    
    apply_effects_in_area(
      attacker, 
      attacker_pos.0, 
      stats.aoe_radius, 
      stats.on_hit_effects, 
      attacker_team
    )
  }
}
/// ------------------------
/// 伤害与战斗模块
/// ------------------------
let global_rng: @random.Rand = @random.Rand::new()

fn apply_damage(attacker: @system.Entity, target: @system.Entity, base_damage: Double) -> Unit {
  if healths.get(target) is Some(health) {
    
    let mut final_damage = base_damage
    
    if combat_stats.get(attacker) is Some(stats) {
      let roll = global_rng.double()
      if roll < stats.crit_rate {
        final_damage = base_damage * 2.0
        println("[Log] Critical Hit!")
      }
    }

    let new_health = { ..health, current: health.current - final_damage }
    healths.set(target, new_health)
  }
}

fn execute_melee_attack(attacker: @system.Entity, target: @system.Entity, stats: CombatStats) -> Unit {
  println("[Log] Executing Melee Attack from \{attacker} to \{target}")
  apply_all_effects(attacker, target, stats.on_hit_effects)
}
fn apply_effects_in_area(
    source: @system.Entity,          // 效果的来源 (攻击者/区域制造者)
    origin_pos: @math.Vec2D,         // 效果的中心点
    radius: Double,                  // 效果的半径
    effects: Array[OnHitEffect],     // 要施加的“效果工具箱”
    source_team: Team                // 来源的阵营
) -> Unit {
  // 1. 遍历所有单位，检查是否在范围内且为敌方
  for unit in all_units.val {
    if teams.get(unit) is Some(unit_team) && unit_team != source_team {
      if @position.positions.get(unit) is Some(unit_pos) {
        // 2. 检查是否在伤害半径内
        if unit_pos.0.distance_to(origin_pos) <= radius {
          // 3. 对范围内的每个敌人，应用全套效果
          apply_all_effects(source, unit, effects)
        }
      }
    }
  }
}

pub enum OnHitEffect {
  DealDamage(Double, Option[VFX_Type])              // 造成 xx 点伤害
  ///(buff种类,持续时间)
  ApplyBuff(BuffType, Double, Option[VFX_Type])     // 施加 xx Buff，持续 yy 秒
  ///(半径,持续时间,每秒伤害)
  CreateHazardousArea(
    Array[OnHitEffect], // 该区域每次触发时的效果
    Double,                      // 区域半径
    Double, 
    Option[VFX_Type]                   // 区域持续时间
  )
}
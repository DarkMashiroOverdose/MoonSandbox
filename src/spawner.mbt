const MAP_WIDTH: Double = 800.0
const MAP_HEIGHT: Double = 600.0
// 敌人生成在屏幕外的一个缓冲距离
const SPAWN_PADDING: Double = 50.0

// --- 敌人生成器状态 ---
// 两波敌人之间的间隔时间（秒）
const INITIAL_SPAWN_INTERVAL: Double = 10.0 
let spawn_timer: Ref[Double] = Ref::new(INITIAL_SPAWN_INTERVAL)
let wave_count: Ref[Int] = Ref::new(0)

fn get_random_edge_position() -> @math.Vec2D {
  // 随机选择一条边：0=上, 1=下, 2=左, 3=右
  let side = global_rng.int(limit=4)
  
  let mut x = 0.0
  let mut y = 0.0

  match side {
    0 => { // 上边
      x = global_rng.double() * MAP_WIDTH
      y = -SPAWN_PADDING
    }
    1 => { // 下边
      x = global_rng.double() * MAP_WIDTH
      y = MAP_HEIGHT + SPAWN_PADDING
    }
    2 => { // 左边
      x = -SPAWN_PADDING
      y = global_rng.double() * MAP_HEIGHT
    }
    _ => { // 右边 (用 _ 来处理 side == 3 的情况)
      x = MAP_WIDTH + SPAWN_PADDING
      y = global_rng.double() * MAP_HEIGHT
    }
  }
  return @math.Vec2D(x, y)
}

pub fn endless_spawner_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0
  spawn_timer.val -= delta_seconds

  if spawn_timer.val <= 0.0 {
    spawn_timer.val = INITIAL_SPAWN_INTERVAL
    wave_count.val += 1
    println("[Game] Wave \{wave_count.val} starting!")

    let num_to_spawn = 8 + wave_count.val * 2

    let enemy_pool = [
      EnemyType::Grunt, EnemyType::Grunt, EnemyType::Grunt, 
      EnemyType::Archer, EnemyType::Archer,
      EnemyType::TankEnemy,
    ]

    for _i = 0; _i < num_to_spawn; _i = _i + 1 {
      let random_index = global_rng.int(limit=enemy_pool.length())
      let enemy_to_spawn = enemy_pool[random_index]
      let spawn_pos = get_random_edge_position()
      spawn_enemy(enemy_to_spawn, spawn_pos)
    }
  }
}
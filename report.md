# 操作系统调试报告

## 调试环境

    WSL Ubuntu 14.04 trusty
    qemu 2.0.0
    gdb 7.7.1

## 相关文件

* compile_kernel.sh 编译 Linux 内核脚本
* config.txt 配置内核编译选项时的注记
* run-qemu.sh 在 wsl 中启动 qemu 虚拟机运行 Linux 内核
* run-gdb.sh 启动 gdb 进行调试
* initrd.img-nixos nixos 镜像中的 initrd 镜像

另外还有 linux-4.14.30.tar.xz ，可以在 www.kernel.org 上获得

## 实验步骤

1. 下载 linux 内核
1. 在 wsl 中用 apt 安装必要软件，如 qemu
1. 在 Windows 中安装必要软件，如 vncviewer
1. 运行 compile_kernel.sh
1. 按照 config.txt 中的注记进行内核编译配置
1. 运行 run-qemu.sh
1. 打开 vncviewer，连接 :2
1. 运行 run-gdb.sh ，调试linux内核s

## 内核在启动过程中的部分事件
```c
cgroup_init_early();        // cgroup的早期初始化
vfs_caches_init_early();    // vfs的早期初始化
mm_init();                  // 内存管理模块的初始化
radix_tree_init();          // 基数树的初始化
sched_init();               // 进程调度器初始化
vfs_caches_init();          // vfs初始化
signals_init();             // 信号量初始化
cgroup_init();              // cgroup初始化
```

在调试 start_kernel 过程中，我单步进入了 sched_init, mm_init, signals_init 和 radix_tree_init， 发现做的大多是与内存和 CPU 相关的初始化。因为不熟悉 Linux 内核架构，所以只能通过函数名大概猜出代码的含义。

例如在 radix_tree_init 中，这段代码可能是在分配缓冲区内存
```c
radix_tree_node_cachep = kmem_cache_create("radix_tree_node",
                            sizeof(struct radix_tree_node), 0,
                            SLAB_PANIC | SLAB_RECLAIM_ACCOUNT,
                            radix_tree_node_ctor);
```

又如，在 signals_init 中，这段代码可能也是在分配内存空间
```c
sigqueue_cachep = KMEM_CACHE(sigqueue, SLAB_PANIC);
```

sched_init 则要更复杂一些，有一些关于cpu的优化不太看得懂

初始化调度时钟（可能和时间片有关）
```c
sched_clock_init();
```

与 CPU 相关的初始化，似乎和负载均衡有关
```c
for_each_possible_cpu(i) {
                per_cpu(load_balance_mask, i) = (cpumask_var_t)kzalloc_node(
                        cpumask_size(), GFP_KERNEL, cpu_to_node(i));
                per_cpu(select_idle_mask, i) = (cpumask_var_t)kzalloc_node(
                        cpumask_size(), GFP_KERNEL, cpu_to_node(i));
        }
```
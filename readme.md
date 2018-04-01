# 操作系统调试报告

## 调试环境

    WSL Ubuntu 16.04
    qemu 2.0.0
    gdb 8.1

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
### `x86_64_start_kernel` 函数。
```c
/* Kill off the identity-map trampoline */
reset_early_page_tables();
clear_bss();
clear_page(init_top_pgt);
```
这几个函数调用清除了最开始的identity-map，初始化了`bss`数据段，为更换内存映射方式作准备。另外，如果没有开启硬件加速，`clear_bss`函数在qemu下相当耗时。

```c
copy_bootdata(__va(real_mode_data));
/*
* Load microcode early on BSP.
*/
load_ucode_bsp();

/* set init_top_pgt kernel high mapping*/
init_top_pgt[] = early_top_pgt[];
x86_64_start_reservations(real_mode_data);
```
`copy_bootdata` 函数初始化了 `real_mode_data` ，`init_top_pgt[] = early_top_pgt[];` 初始化了内核的内存映射。 
经过充分的准备之后，调用了 `x86_64_start_reservations` 函数，准备从实模式进入保护模式。


在 `x86_64_start_reservations` 函数的入口处有如下判断。
```c
/* version is always not zero if it is copied */
if (!boot_params.hdr.version)
        copy_bootdata(__va(real_mode_data));
```
从注释可以看出，这是在用一个字段来检测 real_mode_data 是否已经成功复制，如果没有复制，则需要再次复制。从这里我们看出 linux 内核维护者严谨的态度。涉及底层的代码是在和硬件打交道，硬件的很多行为并不是很稳定，因此内核开发者需要对很多看起来不可能发生的情况进行处理，以确保代码运行正确。

之后就是一些与平台相关的初始化，然后就调用 `start_kernel` ，进入了内核启动函数。
```c
x86_early_init_platform_quirks();

switch (boot_params.hdr.hardware_subarch) {
case X86_SUBARCH_INTEL_MID:
        x86_intel_mid_early_setup();
        break;
default:
        break;
}

start_kernel();
```

### start_kernel 函数

`start_kernel` 的部分函数
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

在调试 start_kernel 过程中，我单步进入了 sched_init, mm_init, signals_init 和 radix_tree_init， 发现里面做的大多是与内存和 CPU 相关的初始化。因为不熟悉 Linux 内核架构，所以只能通过函数名大概猜出代码的含义。

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

我重点观察了与 `cgroup` 相关的初始化。

`cgroup_init_early`函数对 `c_group` 子系统的数据结构进行了一些初始化

```c
for_each_subsys(ss, i) {
        WARN(!ss->css_alloc || !ss->css_free || ss->name || ss->id,
                "invalid cgroup_subsys %d:%s css_alloc=%p css_free=%p id:name=%d:%s\n",
                i, cgroup_subsys_name[i], ss->css_alloc, ss->css_free,
                ss->id, ss->name);
        WARN(strlen(cgroup_subsys_name[i]) > MAX_CGROUP_TYPE_NAMELEN,
                "cgroup_subsys_name %s too long\n", cgroup_subsys_name[i]);

        ss->id = i;
        ss->name = cgroup_subsys_name[i];
        if (!ss->legacy_name)
                ss->legacy_name = cgroup_subsys_name[i];

        if (ss->early_init)
                cgroup_init_subsys(ss, true);
}
```
可以看到，在初始化的过程中，仍然有对数据合法性的检查。`cgroup_init_subsys` 函数复制初始化每个子系统（在cgroup中，每个资源就是一个子系统）。

打印 `cgroup_subsys_name[i]` ，可以看到，当前正在初始化 `cpu` 子系统
```
(gdb) p cgroup_subsys_name[i]
1: cgroup_subsys_name[i] = 0xffffffff81fd2b70 "cpu"
```

进入 `cgroup_init_subsys` ， `cgroup_init_subsys` 在函数入口处锁上了互斥锁
```c
mutex_lock(&cgroup_mutex);
```
之后就是一些对 css (cgroup_subsys_state) 的初始化
```c
INIT_LIST_HEAD(&ss->cfts);
css = ss->css_alloc(cgroup_css(&cgrp_dfl_root.cgrp, ss));
idr_init(&ss->css_idr);
INIT_LIST_HEAD(&ss->cfts);
ss->root = &cgrp_dfl_root;
css = ss->css_alloc(cgroup_css(&cgrp_dfl_root.cgrp, ss));
BUG_ON(IS_ERR(css));
css = ss->css_alloc(cgroup_css(&cgrp_dfl_root.cgrp, ss));
BUG_ON(IS_ERR(css));
init_and_link_css(css, ss, &cgrp_dfl_root.cgrp);
css->flags |= CSS_NO_REF;
```
在函数结束的时候，释放了互斥锁
```c
mutex_unlock(&cgroup_mutex);
```

`cgroup` 的初期初始化就告一段落了，下面进行的是一些其他内核初始化，一段时间后，`start_kernel` 函数调用 `cgroup_init` ，对 cgroup 进行进一步初始化。

cgroup_init 的注释如下
```c
/*
 * cgroup_init - cgroup initialization
 * 
 * Register cgroup filesystem and /proc file, and initialize
 * any subsystems that didn't request early init.
 */
```
注释解释了 cgroup_init 的大致功能：注册 cgroup 的文件系统和 /proc 文件，并且初始化一些不需要提前初始化的子系统。

这里初始化的操作和 early 中的类似。

```c
for_each_subsys(ss, ssid) {
        if (ss->early_init) {
                struct cgroup_subsys_state *css =
                        init_css_set.subsys[ss->id];

                css->id = cgroup_idr_alloc(&ss->css_idr, css, 1, 2,
                                        GFP_KERNEL);
                BUG_ON(css->id < 0);
        } else {
                cgroup_init_subsys(ss, false);
        }

        list_add_tail(&init_css_set.e_cset_node[ssid],
                        &cgrp_dfl_root.cgrp.e_csets[ssid]);

        /*
        * Setting dfl_root subsys_mask needs to consider the
        * disabled flag and cftype registration needs kmalloc,
        * both of which aren't available during early_init.
        */
        if (cgroup_disable_mask & (1 << ssid)) {
                static_branch_disable(cgroup_subsys_enabled_key[ssid]);
                printk(KERN_INFO "Disabling %s control group subsystem\n",
                        ss->name);
                continue;
        }

        if (cgroup1_ssid_disabled(ssid))
                printk(KERN_INFO "Disabling %s control group subsystem in v1 mounts\n",
                        ss->name);

        cgrp_dfl_root.subsys_mask |= 1 << ss->id;

        /* implicit controllers must be threaded too */
        WARN_ON(ss->implicit_on_dfl && !ss->threaded);

        if (ss->implicit_on_dfl)
                cgrp_dfl_implicit_ss_mask |= 1 << ss->id;
        else if (!ss->dfl_cftypes)
                cgrp_dfl_inhibit_ss_mask |= 1 << ss->id;

        if (ss->threaded)
                cgrp_dfl_threaded_ss_mask |= 1 << ss->id;

        if (ss->dfl_cftypes == ss->legacy_cftypes) {
                WARN_ON(cgroup_add_cftypes(ss, ss->dfl_cftypes));
        } else {
                WARN_ON(cgroup_add_dfl_cftypes(ss, ss->dfl_cftypes));
                WARN_ON(cgroup_add_legacy_cftypes(ss, ss->legacy_cftypes));
        }

        if (ss->bind)
                ss->bind(init_css_set.subsys[ssid]);

        mutex_lock(&cgroup_mutex);
        css_populate_dir(init_css_set.subsys[ssid]);
        mutex_unlock(&cgroup_mutex);
}

```

在这里的初始化中，ss->name 出现了以下子系统
`freezer` `cpuacct` `cpu` `cpuset` ，在初始化时，循环体会判断是否已经在 early 里初始化过，如果没有初始化过，则还要调用 `cgroup_init_subsys` 进行子系统的初始化。

到此为止，cgroup 的初始化就结束了。
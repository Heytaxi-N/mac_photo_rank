# 照片转存

一个本地 macOS 小工具，用来把「照片」或 Finder 里的图片批量导出到微店商品图目录，并按点击顺序重命名。

## 使用

1. 运行打包脚本：

   ```bash
   scripts/build_app.sh
   ```

2. 打开生成的 App：

   ```bash
   open dist/照片转存.app
   ```

3. 在 App 里输入文件夹名，例如 `红标短裤`。
4. 从「照片」App 或 Finder 拖入图片。
5. 按目标顺序点击缩略图，编号从 `01` 开始；再次点击可取消编号。
6. 点击「导出」。

图片会导出到：

```text
/Users/nick/Downloads/微店批量上架/商品图/<文件夹名>/
```

输出文件统一为 JPG，例如：

```text
红标短裤01.jpg
红标短裤02.jpg
红标短裤03.jpg
```

## 重名处理

如果目标文件夹已经存在，App 会提示：

- 覆盖并重新导出：先清空旧文件夹，再写入新图片。
- 自动新建后缀文件夹：例如 `红标短裤-2`。
- 取消：不做任何导出。

## 开发验证

核心逻辑测试：

```bash
swift run PhotoTransferCoreTestRunner
```

编译 App：

```bash
swift build
```

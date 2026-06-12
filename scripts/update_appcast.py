#!/usr/bin/env python3
"""增量更新 Sparkle appcast.xml：插入/替换一条 <item>。

用法:
  update_appcast.py <appcast.xml> <app_name> <short_version> <build> \
                    <ed_signature> <length> <download_url> [release_notes_url]

- appcast.xml 不存在时自动创建骨架。
- 若已存在相同 build 的 item 则替换，否则插入到最前（最新版在前）。
- build 号（CFBundleVersion）是 Sparkle 判断新旧的依据，必须递增。
"""
import sys
from datetime import datetime, timezone
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def skeleton(app_name: str) -> ET.ElementTree:
    # register_namespace 会在写出时自动声明 xmlns:sparkle，无需手动 set（否则重复）
    rss = ET.Element("rss", {"version": "2.0"})
    ch = ET.SubElement(rss, "channel")
    ET.SubElement(ch, "title").text = f"{app_name} Updates"
    ET.SubElement(ch, "description").text = f"{app_name} 自动更新源"
    ET.SubElement(ch, "language").text = "zh"
    return ET.ElementTree(rss)


def sp(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def main() -> int:
    if len(sys.argv) < 8:
        print(__doc__)
        return 2
    (path, app_name, version, build, signature, length, download_url) = sys.argv[1:8]
    notes_url = sys.argv[8] if len(sys.argv) > 8 else None

    try:
        tree = ET.parse(path)
    except (FileNotFoundError, ET.ParseError):
        tree = skeleton(app_name)

    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        channel = ET.SubElement(root, "channel")

    # 删除同 build 的旧 item（幂等）
    for item in channel.findall("item"):
        v = item.find(sp("version"))
        if v is not None and v.text == build:
            channel.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = version
    ET.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )
    ET.SubElement(item, sp("version")).text = build            # CFBundleVersion
    ET.SubElement(item, sp("shortVersionString")).text = version
    ET.SubElement(item, sp("minimumSystemVersion")).text = "12.0"
    if notes_url:
        ET.SubElement(item, sp("releaseNotesLink")).text = notes_url
    ET.SubElement(item, "enclosure", {
        "url": download_url,
        "length": length,
        "type": "application/octet-stream",
        sp("edSignature"): signature,
        sp("os"): "macos",
    })

    # 插入到第一个 item 之前（最新在前）
    existing = channel.find("item")
    if existing is not None:
        channel.insert(list(channel).index(existing), item)
    else:
        channel.append(item)

    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    print(f"appcast 已更新: {app_name} {version} (build {build})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

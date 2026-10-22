from pathlib import Path

from PIL import Image

project = Path(__file__).resolve().parents[1]
source = project / "assets/branding/fc-career-live-icon.png"
resources = project / "android/app/src/main/res"
with Image.open(source) as icon:
    if icon.width != icon.height:
        raise ValueError("The application icon must be the complete square image")
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        destination = resources / f"mipmap-{density}/ic_launcher.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        icon.resize((size, size), Image.Resampling.LANCZOS).save(destination)
        print(f"{destination.relative_to(project)}: {size}x{size}")

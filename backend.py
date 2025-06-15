from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import json
import shutil
import subprocess
import time
import re
from pathlib import Path
import yt_dlp
from datetime import datetime

app = Flask(__name__)
CORS(app)

DOWNLOAD_DIR = Path.home() / "Desktop" / "makecut" / "downloads"
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

HISTORY_FILE = DOWNLOAD_DIR / "history.json"
AUTOSAVE_FILE = DOWNLOAD_DIR / "autosave.json"

def wait_for_file_release(filepath, retries=30):
    for _ in range(retries):
        try:
            with open(filepath, 'a'):
                return True
        except Exception:
            time.sleep(0.5)
    return False

def sanitize_filename(name):
    name = re.sub(r'[\\/*?:"<>|]', "", name)
    return name.strip().replace(" ", "_")[:80]

def open_with_default_media_player(filepath):
    try:
        if Path(filepath).exists():
            subprocess.Popen(f'start "" "{filepath}"', shell=True)
    except Exception as e:
        print(f"Failed to open media player: {e}")

def is_snapchat_url(url):
    return "snapchat.com" in url

def get_best_video_format_id(url):
    try:
        with yt_dlp.YoutubeDL({'quiet': True}) as ydl:
            info = ydl.extract_info(url, download=False)
            formats = info.get("formats")
            if not formats:
                return "best"
            video_only = [
                f for f in formats
                if f.get("acodec") == "none" and f.get("vcodec") != "none"
            ]
            video_only = sorted(video_only, key=lambda x: x.get("height", 0), reverse=True)
            return video_only[0]["format_id"] if video_only else "best"
    except:
        return "best"

def download_video(url, include_audio, quality):
    try:
        suffix = "_audio-on" if include_audio else "_audio-off"
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        outtmpl = str(DOWNLOAD_DIR / f'%(title)s{suffix}_{timestamp}.%(ext)s')

        height = quality.replace("p", "")
        ydl_opts = {
            'quiet': True,
            'noplaylist': True,
            'outtmpl': outtmpl,
            'merge_output_format': 'mp4',
            'ffmpeg_location': 'ffmpeg',
            'ignoreerrors': True,
            'no_warnings': True,
            'geo_bypass': True
        }

        if include_audio:
            ydl_opts['format'] = f'bestvideo[height<={height}]+bestaudio/best[height<={height}]/best'
        else:
            ydl_opts['format'] = get_best_video_format_id(url)
            ydl_opts['postprocessors'] = []

        if is_snapchat_url(url):
            ydl_opts['user_agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            raw_file = ydl.prepare_filename(info).replace(".webm", ".mp4").replace(".mkv", ".mp4")
            clean_name = sanitize_filename(Path(raw_file).stem) + ".mp4"
            final_path = DOWNLOAD_DIR / clean_name
            temp_path = DOWNLOAD_DIR / f"temp_{clean_name}"

            os.system(f'ffmpeg -y -i "{raw_file}" -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k "{temp_path}"')

            if wait_for_file_release(temp_path):
                shutil.move(temp_path, final_path)

            if wait_for_file_release(raw_file):
                try:
                    os.remove(raw_file)
                except:
                    pass

            if not include_audio:
                muted_path = str(final_path).replace(".mp4", "_muted.mp4")
                os.system(f'ffmpeg -y -i "{final_path}" -c copy -an "{muted_path}"')
                if os.path.exists(muted_path) and wait_for_file_release(final_path):
                    os.remove(final_path)
                    shutil.move(muted_path, final_path)

        open_with_default_media_player(str(final_path))
        return True, str(final_path), ""

    except Exception as e:
        return False, None, f"{type(e).__name__}: {e}"

@app.route("/download", methods=["POST"])
def download():
    data = request.get_json()
    url = data.get("url")
    include_audio = data.get("audio", True)
    quality = data.get("quality", "1080p")

    if not url:
        return jsonify({"status": "fail", "message": "No URL provided"}), 400

    success, filepath, error = download_video(url, include_audio, quality)

    if success:
        try:
            autosave = False
            if AUTOSAVE_FILE.exists():
                with open(AUTOSAVE_FILE, "r") as f:
                    autosave = json.load(f).get("enabled", False)
        except:
            pass

        if autosave:
            try:
                with open(HISTORY_FILE, "r") as f:
                    history = json.load(f)
            except:
                history = []

            if filepath not in history:
                history.append(filepath)
                with open(HISTORY_FILE, "w") as f:
                    json.dump(history, f)

        return jsonify({
            "status": "success",
            "path": str(DOWNLOAD_DIR),
            "file": os.path.basename(filepath)
        })

    return jsonify({"status": "fail", "message": error}), 500

@app.route("/history", methods=["GET"])
def history():
    try:
        with open(HISTORY_FILE, "r") as f:
            filenames = json.load(f)
    except:
        filenames = []

    data = []
    for f in filenames:
        path = Path(f)
        if path.exists():
            size = round(path.stat().st_size / (1024 * 1024), 1)
            data.append({
                "filename": path.name,
                "size": f"{size} MB",
                "path": str(path)
            })

    return jsonify(data)

@app.route("/rename", methods=["POST"])
def rename():
    data = request.get_json()
    old_path = data.get("oldPath")
    new_name = data.get("newName")

    if not old_path or not new_name:
        return jsonify({"status": "fail", "message": "Missing data"}), 400

    old_file = Path(old_path)
    new_file = old_file.parent / (sanitize_filename(new_name) + ".mp4")

    try:
        old_file.rename(new_file)

        try:
            with open(HISTORY_FILE, "r") as f:
                history = json.load(f)
        except:
            history = []

        updated = [str(new_file) if h == old_path else h for h in history]
        with open(HISTORY_FILE, "w") as f:
            json.dump(updated, f)

        return jsonify({"status": "success", "path": str(new_file)})

    except Exception as e:
        return jsonify({"status": "fail", "message": str(e)}), 500

@app.route("/save", methods=["POST"])
def save_video():
    data = request.get_json()
    filepath = data.get("path")
    if not filepath or not Path(filepath).exists():
        return jsonify({"status": "fail", "message": "File not found"}), 400
    open_with_default_media_player(filepath)
    return jsonify({"status": "success"})

@app.route("/autosave", methods=["GET"])
def get_autosave():
    try:
        with open(AUTOSAVE_FILE, "r") as f:
            return jsonify(json.load(f))
    except:
        return jsonify({"enabled": False})

@app.route("/autosave", methods=["POST"])
def set_autosave():
    data = request.get_json()
    enabled = data.get("enabled", False)
    with open(AUTOSAVE_FILE, "w") as f:
        json.dump({"enabled": enabled}, f)
    return jsonify({"status": "updated", "enabled": enabled})

import os

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 10000))
    app.run(host='0.0.0.0', port=port)


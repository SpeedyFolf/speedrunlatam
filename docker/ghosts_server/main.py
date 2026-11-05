import os
import traceback
from flask import Flask, request
from ghost_store import GhostStore

app = Flask (__name__)
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024 * 1024 # 8 MB

ghost_store = GhostStore (os.environ.get("GHOSTS_DIR", "./ghosts"))

@app.route("/ghost")
def serve_ghost ():
    ghost_name = request.args.get("name")

    if ghost_name is None:
        return {"error": "Ghost name not specified"}

    try:
        json_file = ghost_store.download_ghost (ghost_name)
        return json_file
    except Exception as e:
        print(traceback.format_exc ())
        return {"error": "Ghost does not exist on the server"}, 400

@app.route ("/save_ghost", methods=["POST"])
def upload_ghost ():
    ghost_name = request.args.get("name")

    if ghost_name is None:
        return {"error": "Ghost name not specified"}

    try:
        ghost_content = request.get_data (as_text = True)
        ghost_store.upload_ghost (ghost_name, ghost_content)
        return {"error": "success"}, 200
    except Exception as e:
        print(traceback.format_exc ())
        return {"error": "Failed to upload ghost"}, 400

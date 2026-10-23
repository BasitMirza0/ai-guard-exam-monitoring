# Google Colab development deployment

This documents the real backend in [`../backend/main.py`](../backend/main.py).
Colab/ngrok is temporary development/demo infrastructure, not permanent or
production hosting. The notebook itself remains external; no token or notebook
output is committed here.

## Startup sequence

1. Use a Colab runtime with Python 3.10+ and install the backend dependencies:

   ```python
   %cd /content
   !pip install -r /content/drive/MyDrive/FYP_AI/backend/requirements.txt
   ```

   If the repository is checked out elsewhere in Drive, use that actual path.
   Install `pyngrok` separately if the Colab image does not already provide it;
   it is only tunnel tooling and is not imported by the API.

2. Mount Google Drive using Colab's authentication flow, then copy the private
   model into the path the backend loads at import:

   ```python
   from google.colab import drive
   drive.mount('/content/drive')
   !cp /content/drive/MyDrive/FYP_AI/best_model_merged.pt /content/best_model_merged.pt
   ```

3. Start the API from the backend directory so `main:app` resolves:

   ```python
   %cd /content/drive/MyDrive/FYP_AI/backend
   !uvicorn main:app --host 0.0.0.0 --port 8000 > /tmp/ai_guard_uvicorn.log 2>&1 &
   ```

   The API imports YOLO and loads `/content/best_model_merged.pt` during startup.
   If the weights are absent or invalid, import fails and `/health` will not be
   available. Inspect the local server log without exposing credentials.

4. Store the ngrok token under **Colab Secrets** as `NGROK_AUTHTOKEN`, grant the
   notebook access, and start the tunnel:

   ```python
   from google.colab import userdata
   from pyngrok import ngrok

   token = userdata.get('NGROK_AUTHTOKEN')
   if not token:
       raise RuntimeError('Set NGROK_AUTHTOKEN in Colab Secrets')
   ngrok.set_auth_token(token)
   tunnel = ngrok.connect(8000)
   print(tunnel.public_url)  # URL only; never print token.
   ```

5. Check the tunnel's `/health` URL and then run consented image/video demos.
   Configure Flutter with the current HTTPS tunnel URL:

   ```sh
   flutter run --dart-define=API_BASE_URL=https://your-current-tunnel.example
   ```

6. Stop the tunnel and runtime after the demo. Runtime restarts erase in-memory
   jobs and `/tmp` outputs. Successful video output has no API deletion/TTL, so
   clean it up through the runtime or terminate the runtime according to your
   data-retention policy.

The backend enables wildcard CORS and has no API authentication. A public tunnel
is not access control. Do not send private exam media. Do not put the token in a
notebook cell, output, environment file, Flutter define, source file or workflow.
If a notebook is later added, clear all outputs/execution state and scan it for
tokens, identities, Drive listings and private images before publication.

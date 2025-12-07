import io
import base64
import numpy as np
from fastapi import FastAPI, UploadFile, File
from ultralytics import YOLO
from PIL import Image
import cv2

app = FastAPI()

# Load Model (Thêm device=0 nếu có GPU)
try:
    model = YOLO('best.pt') 
    print("AI Model loaded successfully!")
except Exception as e:
    print(f"Error loading model: {e}")

@app.post("/predict")
async def predict_pothole(file: UploadFile = File(...)):
    try:
        image_data = await file.read()
        image = Image.open(io.BytesIO(image_data))
        
       
        results = model.predict(image, conf=0.10)
        result = results[0]

       
        res_plotted = result.plot(conf=False, font_size=1.5) 
        
        res_plotted = cv2.cvtColor(res_plotted, cv2.COLOR_BGR2RGB)
        
        im_pil = Image.fromarray(res_plotted)
        buffer = io.BytesIO()
        im_pil.save(buffer, format="JPEG")
        img_str = base64.b64encode(buffer.getvalue()).decode("utf-8")

        status = "green"
        if result.boxes:
            count = len(result.boxes)
            if count >= 3:
                status = "red"
            elif count >= 1:
                status = "yellow"

        return {
            "success": True,
            "status": status,
            "pothole_count": len(result.boxes) if result.boxes else 0,
            "image_base64": img_str  # <--- Đây là chuỗi chứa ảnh kết quả
        }

    except Exception as e:
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
import io
import base64
import time
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
    start_time = time.time()
    print("\n" + "="*60)
    print("🚀 NHẬN REQUEST MỚI")
    print("="*60)
    
    try:
        # Bước 1: Đọc ảnh
        print("📖 [1] Đọc ảnh từ request...")
        image_data = await file.read()
        image_size = len(image_data)
        print(f"   ✅ Đã đọc: {image_size:,} bytes ({image_size/1024/1024:.2f} MB)")
        
        image = Image.open(io.BytesIO(image_data))
        print(f"   📐 Kích thước ảnh: {image.size}")
        read_time = time.time() - start_time
        print(f"   ⏱️  Thời gian đọc: {read_time:.2f}s")

        # Bước 2: Chạy AI
        print("\n🤖 [2] Chạy AI model...")
        ai_start = time.time()
        results = model.predict(image, conf=0.10, verbose=False)
        result = results[0]
        ai_time = time.time() - ai_start
        print(f"   ✅ AI xử lý xong: {ai_time:.2f}s")
        print(f"   🎯 Phát hiện: {len(result.boxes) if result.boxes else 0} ổ gà")

        # Bước 3: Vẽ bounding box
        print("\n🎨 [3] Vẽ bounding box...")
        plot_start = time.time()
        res_plotted = result.plot(conf=False, font_size=1.5) 
        res_plotted = cv2.cvtColor(res_plotted, cv2.COLOR_BGR2RGB)
        plot_time = time.time() - plot_start
        print(f"   ✅ Vẽ xong: {plot_time:.2f}s")
        
        # Bước 4: Convert sang base64
        print("\n📦 [4] Convert sang base64...")
        encode_start = time.time()
        im_pil = Image.fromarray(res_plotted)
        buffer = io.BytesIO()
        im_pil.save(buffer, format="JPEG", quality=85)
        img_str = base64.b64encode(buffer.getvalue()).decode("utf-8")
        encode_time = time.time() - encode_start
        print(f"   ✅ Encode xong: {encode_time:.2f}s")
        print(f"   📊 Base64 size: {len(img_str):,} ký tự")

        # Bước 5: Xác định status
        status = "green"
        if result.boxes:
            count = len(result.boxes)
            if count >= 3:
                status = "red"
            elif count >= 1:
                status = "yellow"

        total_time = time.time() - start_time
        print(f"\n✅ HOÀN THÀNH!")
        print(f"   ⏱️  Tổng thời gian: {total_time:.2f}s")
        print(f"   📊 Breakdown:")
        print(f"      - Đọc ảnh: {read_time:.2f}s ({read_time/total_time*100:.1f}%)")
        print(f"      - AI: {ai_time:.2f}s ({ai_time/total_time*100:.1f}%)")
        print(f"      - Vẽ: {plot_time:.2f}s ({plot_time/total_time*100:.1f}%)")
        print(f"      - Encode: {encode_time:.2f}s ({encode_time/total_time*100:.1f}%)")
        print(f"   🎯 Trạng thái: {status}")
        print("="*60 + "\n")

        return {
            "success": True,
            "status": status,
            "pothole_count": len(result.boxes) if result.boxes else 0,
            "image_base64": img_str,
            "processing_time": round(total_time, 2),
        }

    except Exception as e:
        error_time = time.time() - start_time
        print(f"\n❌ LỖI sau {error_time:.2f}s: {e}")
        print("="*60 + "\n")
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
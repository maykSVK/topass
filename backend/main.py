from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from physics import Simulation
import uvicorn
import traceback

app = FastAPI(title="Topographic Agents API")

# Configure CORS to allow the Flutter web frontend to communicate with the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify the actual origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/simulate")
async def simulate(image: UploadFile = File(...), duration: int = Form(15)):
    """
    Receives an image, runs the topographic agents physics simulation,
    and returns the paths and note events.
    """
    try:
        # Read the uploaded image bytes
        image_bytes = await image.read()
        
        # Calculate number of frames (40 frames per second)
        frames = duration * 40
        
        # Initialize and run the simulation
        sim = Simulation(image_bytes=image_bytes, num_agents=12, frames=frames, contour_interval=10)
        result = sim.run()
        
        return result
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    # Run the server locally on port 8000
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

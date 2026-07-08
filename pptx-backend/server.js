const express = require("express");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(express.json());
app.get("/", (req, res) => {
  res.send("SERVER OK");
});
app.get("/api/presentation/manifest", (req, res) => {
  res.json({
    presentationId: "demo-001",
    title: "Demo PPTX",
    slides: [
      {
        id: "slide-1",
        index: 0,
        kind: "standard",
        title: "Hello",
        render: {
          format: "svg",
          content: "<svg width='300' height='200'><rect width='300' height='200' fill='blue'/></svg>"
        },
        meta: {
          width: 1280,
          height: 720
        }
      },
      {
        id: "slide-ar",
        index: 1,
        kind: "ar",
        title: "AR Scene",
        ar: {
          modelUrl: "http://127.0.0.1:3000/assets/model.glb",
          anchor: "center",
          scale: 1.0,
          rotationY: 0,
          offsetX: 0,
          offsetY: 0
        }
      }
    ]
  });
});

app.listen(3000, "0.0.0.0", () => {
  console.log("Backend running on http://0.0.0.0:3000");
});
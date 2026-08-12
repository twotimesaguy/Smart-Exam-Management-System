import json
import os
from typing import Any

import numpy as np


class FaceRecognitionService:
    def __init__(self) -> None:
        self._model: Any | None = None
        self._backend = "opencv"
        try:
            from insightface.app import FaceAnalysis

            model = FaceAnalysis(name="buffalo_l")
            model.prepare(ctx_id=-1)
            self._model = model
            self._backend = "insightface"
        except Exception:
            self._model = None

    @property
    def backend(self) -> str:
        return self._backend

    @property
    def match_threshold(self) -> float:
        default_threshold = "0.72" if self._model is not None else "0.86"
        return float(os.getenv("FACE_MATCH_THRESHOLD", default_threshold))

    def embedding_from_bytes(self, image_bytes: bytes) -> list[float]:
        if self._model is not None:
            embedding = self._insightface_embedding(image_bytes)
            if embedding:
                return embedding

        return self._opencv_embedding(image_bytes)

    def _insightface_embedding(self, image_bytes: bytes) -> list[float]:
        import cv2

        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("The uploaded image could not be decoded.")

        faces = self._model.get(image)
        if len(faces) != 1:
            raise ValueError("Upload an image with exactly one clear face.")

        embedding = faces[0].embedding.astype(float)
        norm = np.linalg.norm(embedding)
        if norm == 0:
            raise ValueError("Could not generate a face embedding.")

        return (embedding / norm).tolist()

    def _opencv_embedding(self, image_bytes: bytes) -> list[float]:
        import cv2

        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("The uploaded image could not be decoded.")

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        face = self._largest_detected_face(gray)
        if face is None:
            face = gray

        resized = cv2.resize(face, (64, 64), interpolation=cv2.INTER_AREA)
        equalized = cv2.equalizeHist(resized)
        normalized = equalized.astype(np.float32) / 255.0

        dct = cv2.dct(normalized)[:24, :24].flatten()
        hist = cv2.calcHist([equalized], [0], None, [64], [0, 256]).flatten()
        hist_sum = hist.sum()
        if hist_sum:
            hist = hist / hist_sum

        values = np.concatenate([dct, hist])
        values = values - values.mean()
        norm = np.linalg.norm(values)
        if norm == 0:
            raise ValueError("Could not generate a face embedding.")

        return (values / norm).tolist()

    def _largest_detected_face(self, gray: np.ndarray) -> np.ndarray | None:
        import cv2

        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        detector = cv2.CascadeClassifier(cascade_path)
        faces = detector.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(80, 80),
        )
        if len(faces) == 0:
            return None

        x, y, width, height = max(faces, key=lambda item: item[2] * item[3])
        pad_x = int(width * 0.18)
        pad_y = int(height * 0.22)
        left = max(x - pad_x, 0)
        top = max(y - pad_y, 0)
        right = min(x + width + pad_x, gray.shape[1])
        bottom = min(y + height + pad_y, gray.shape[0])
        return gray[top:bottom, left:right]

    def serialize(self, embedding: list[float]) -> str:
        return json.dumps(embedding)

    def deserialize(self, value: str | None) -> list[float]:
        if not value:
            return []
        return [float(item) for item in json.loads(value)]

    def similarity(self, left: list[float], right: list[float]) -> float:
        if not left or not right or len(left) != len(right):
            return 0.0
        return float(np.dot(np.array(left), np.array(right)))


face_service = FaceRecognitionService()

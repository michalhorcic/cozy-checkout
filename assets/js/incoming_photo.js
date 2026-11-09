const MAX_EDGE = 1920
const JPEG_QUALITY = 0.85

// Decode with the browser's EXIF orientation handling, then write a fresh JPEG.
// PDFs go through unchanged; the full-resolution photo never reaches LiveView.
export async function prepareIncomingPhoto(file) {
  if (file.type === "application/pdf" || (!file.type && /\.pdf$/i.test(file.name))) return file

  const url = URL.createObjectURL(file)
  const image = new Image()
  let canvas
  try {
    image.src = url
    await image.decode()
    const scale = Math.min(1, MAX_EDGE / Math.max(image.naturalWidth, image.naturalHeight))
    canvas = document.createElement("canvas")
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale))
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale))
    const context = canvas.getContext("2d")
    if (!context) throw new Error("Canvas unavailable")
    // Transparent PNG backgrounds become white rather than black in JPEG.
    context.fillStyle = "#fff"
    context.fillRect(0, 0, canvas.width, canvas.height)
    context.drawImage(image, 0, 0, canvas.width, canvas.height)
    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY))
    if (!blob || blob.type !== "image/jpeg") throw new Error("JPEG conversion failed")
    return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", {
      type: "image/jpeg", lastModified: file.lastModified
    })
  } finally {
    image.src = ""
    if (canvas) { canvas.width = 0; canvas.height = 0 }
    URL.revokeObjectURL(url)
  }
}

// Minimal C ABI over libjxl's decoder for Dart FFI.
//
// Decodes the first displayed frame of a JPEG XL image to straight RGBA8,
// with orientation applied and XYB images converted to sRGB, the same
// defaults `djxl` uses for 8-bit output.

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

#include <jxl/decode.h>
#include <jxl/resizable_parallel_runner.h>

#if defined(_WIN32)
#define JXL_NATIVE_EXPORT __declspec(dllexport)
#else
#define JXL_NATIVE_EXPORT __attribute__((visibility("default")))
#endif

enum {
  JXL_NATIVE_OK = 0,
  JXL_NATIVE_INVALID_ARGUMENT = 1,
  JXL_NATIVE_DECODE_FAILED = 2,
  JXL_NATIVE_TRUNCATED = 3,
  JXL_NATIVE_TOO_LARGE = 4,
  JXL_NATIVE_OUT_OF_MEMORY = 5,
};

JXL_NATIVE_EXPORT uint32_t jxl_native_decoder_version(void) {
  return JxlDecoderVersion();
}

JXL_NATIVE_EXPORT void jxl_native_free(void* pointer) { free(pointer); }

JXL_NATIVE_EXPORT int32_t jxl_native_decode(const uint8_t* data, size_t size,
                                            uint64_t max_pixels,
                                            uint8_t** out_rgba,
                                            int32_t* out_width,
                                            int32_t* out_height) {
  if (!data || size == 0 || !out_rgba || !out_width || !out_height) {
    return JXL_NATIVE_INVALID_ARGUMENT;
  }
  *out_rgba = NULL;
  *out_width = 0;
  *out_height = 0;

  int32_t result = JXL_NATIVE_DECODE_FAILED;
  uint8_t* pixels = NULL;
  JxlDecoder* decoder = JxlDecoderCreate(NULL);
  void* runner = JxlResizableParallelRunnerCreate(NULL);
  if (!decoder || !runner) {
    result = JXL_NATIVE_OUT_OF_MEMORY;
    goto done;
  }

  const JxlPixelFormat format = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
  JxlBasicInfo info = {0};
  if (JxlDecoderSetParallelRunner(decoder, JxlResizableParallelRunner,
                                  runner) != JXL_DEC_SUCCESS ||
      JxlDecoderSubscribeEvents(decoder, JXL_DEC_BASIC_INFO |
                                             JXL_DEC_COLOR_ENCODING |
                                             JXL_DEC_FULL_IMAGE) !=
          JXL_DEC_SUCCESS ||
      JxlDecoderSetInput(decoder, data, size) != JXL_DEC_SUCCESS) {
    goto done;
  }
  JxlDecoderCloseInput(decoder);

  for (;;) {
    const JxlDecoderStatus status = JxlDecoderProcessInput(decoder);
    if (status == JXL_DEC_BASIC_INFO) {
      if (JxlDecoderGetBasicInfo(decoder, &info) != JXL_DEC_SUCCESS) goto done;
      const uint64_t count = (uint64_t)info.xsize * info.ysize;
      if (info.xsize == 0 || info.ysize == 0 || info.xsize > INT32_MAX ||
          info.ysize > INT32_MAX || (max_pixels && count > max_pixels) ||
          count > SIZE_MAX / 4) {
        result = JXL_NATIVE_TOO_LARGE;
        goto done;
      }
      JxlResizableParallelRunnerSetThreads(
          runner,
          JxlResizableParallelRunnerSuggestThreads(info.xsize, info.ysize));
    } else if (status == JXL_DEC_COLOR_ENCODING) {
      // Honoured for XYB (lossy) images; others keep their own encoding.
      // (JxlColorEncodingSetToSRGB lives in the encoder library.)
      JxlColorEncoding srgb = {0};
      srgb.color_space = info.num_color_channels == 1 ? JXL_COLOR_SPACE_GRAY
                                                      : JXL_COLOR_SPACE_RGB;
      srgb.white_point = JXL_WHITE_POINT_D65;
      srgb.primaries = JXL_PRIMARIES_SRGB;
      srgb.transfer_function = JXL_TRANSFER_FUNCTION_SRGB;
      srgb.rendering_intent = JXL_RENDERING_INTENT_RELATIVE;
      JxlDecoderSetPreferredColorProfile(decoder, &srgb);
    } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
      size_t buffer_size;
      if (JxlDecoderImageOutBufferSize(decoder, &format, &buffer_size) !=
          JXL_DEC_SUCCESS) {
        goto done;
      }
      free(pixels);
      pixels = (uint8_t*)malloc(buffer_size);
      if (!pixels) {
        result = JXL_NATIVE_OUT_OF_MEMORY;
        goto done;
      }
      if (JxlDecoderSetImageOutBuffer(decoder, &format, pixels, buffer_size) !=
          JXL_DEC_SUCCESS) {
        goto done;
      }
    } else if (status == JXL_DEC_FULL_IMAGE) {
      // First displayed frame of an animation is enough for a still view.
      *out_rgba = pixels;
      *out_width = (int32_t)info.xsize;
      *out_height = (int32_t)info.ysize;
      pixels = NULL;
      result = JXL_NATIVE_OK;
      goto done;
    } else if (status == JXL_DEC_NEED_MORE_INPUT) {
      result = JXL_NATIVE_TRUNCATED;
      goto done;
    } else {
      // JXL_DEC_ERROR, or JXL_DEC_SUCCESS before any frame was produced.
      goto done;
    }
  }

done:
  free(pixels);
  if (runner) JxlResizableParallelRunnerDestroy(runner);
  if (decoder) JxlDecoderDestroy(decoder);
  return result;
}

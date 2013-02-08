{-# LANGUAGE BangPatterns, ScopedTypeVariables, MagicHash #-}

import Control.Monad
import Data.Word
import System.Environment
import GHC.Exts
import GHC.Prim

import Data.Yarr
import Data.Yarr.Shape as S
import Data.Yarr.IO.Image
import Data.Yarr.Benchmarking
import Data.Yarr.Utils.Primitive
import Data.Yarr.Utils.FixedVector


normalizeByte :: Word8 -> Float
normalizeByte w8 = (fromIntegral w8) / 255

normalizedToByte :: Float -> Word8
normalizedToByte f = fromIntegral (truncate (f * 255) :: Int)

main = do
    [cf, imageFile] <- getArgs

    anyImage <- readImage imageFile
    (floatRGBImage :: UArray F L Dim2 (VecList N3 Float)) <-
        safeCompute (loadS fill) $
            mapElems normalizeByte $ readRGBVectors anyImage

    let contrastFactor = read cf
        !cc = 1.02 * (contrastFactor + 1) / (1.02 - contrastFactor)
        contrast comp = clampM 0.0 1.0 (cc * (comp - 0.5) + 0.5)
        delayedContrasted =
            mapElemsM ((return . normalizedToByte) <=< contrast) floatRGBImage

        commonExt = (extent floatRGBImage)
        contrastTimingLoad =
            time "contrast" 10 commonExt (loadP S.fill caps)
    (contrasted :: UArray F L Dim2 (VecList N3 Word8)) <-
        safeCompute contrastTimingLoad delayedContrasted

    writeImage ("t-contrasted-" ++ imageFile) (RGB contrasted)


    -- Unfortunately, without this ↘ signature GHC doesn't inline the function
    let luminosity r g b = (0.21 :: Float) * r + 0.71 * g + 0.07 * b
        {-# INLINE luminosity #-}
        delayedLum = dmap normalizedToByte $ zipElems luminosity floatRGBImage

        {-# INLINE lumTimingLoad #-}
        lumTimingLoad =
            time "luminosity" 10 commonExt
                 (loadP (S.unrolledFill n6 noTouch) caps)
    (lum :: UArray F L Dim2 Word8) <-
        safeCompute lumTimingLoad delayedLum

    writeImage ("t-luminosity-" ++ imageFile) (Grey lum)
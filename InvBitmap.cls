<?

/**
 *    FILE:         InvBitmap.cls
 *    AUTHOR:       Roger Collins
 *    DESCRIPTION:  A set of booleans, implemented in a string
 *
 *    (C) 2023, Sage / Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Sage / Intacct
 *    Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Sage / Intacct Corporation.
 */


// General idea: We maintain an array of CHARS of T or F.
//              We extend the string when writing past the end.
//              We extend in chunks so we're not constantly stretching the string
//              If it needs to be massive, we could switch to BITS in the bytes, but beware of UTF-8 extensions
//                  (i.e. use only the lower 7 bits)
class InvBitmap
{
    const   EXTEND_SIZE     = 1024 * 10;     // extend by this much each time

    /** @var string $bitmap */
    private $bitmap;                // the string of true/false values

    /** @var int $bitmapSize */
    private $bitmapUserSize;        // how many bits has the user set?




    /**
     *      Constructor
     */
    function __construct( int $numberOfBits = 0 )
    {
        $this->bitmap           = '';
        $this->bitmapUserSize   = 0;

        $this->extendTo($numberOfBits);
    }


    /**
     * @param int $size     How big to make the string
     */
    private function extendTo($size)
    {
        if ($this->bitmapUserSize < $size) {
            $realSize = strlen($this->bitmap);
            if ($realSize       < $size) {
                $newSize        = $size + self::EXTEND_SIZE;
                $this->bitmap   = str_pad($this->bitmap, $newSize, 'F');
            }
            $this->bitmapUserSize = $size;  // as if they had written to it already
        }
    }


    /**
     * @return int      How many bits has the user set?
     */
    public function size()
    {
        return $this->bitmapUserSize;   // how many T/Fs the user has set
    }

    /**
     * @param int  $bit         which 'bit' to set, can be off the end of the string.  Bits start with bit 0
     * @param bool $value       set it to true or false
     */
    public function set( int $bit, bool $value)
    {
        if ($bit < 0) {
            throw new Exception("[CODE BUG]Negative bit set");
        }
        $this->extendTo($bit+1);                // bits start with zero, so extend to bit+1
        $this->bitmap[$bit] = $value ? 'T' : 'F';
    }


    /**
     * @param int $bit
     *
     * @return bool
     * @throws Exception
     */
    public function get( int $bit )
    {
        if ($bit < 0) {
            throw new Exception("[CODE BUG]Negative bit get");
        }
        if ($bit >= $this->bitmapUserSize) {    // >= because we're zero based bits
            return false; // well, it can't be true
        }
        return ($this->bitmap[$bit] === 'T');
    }

}


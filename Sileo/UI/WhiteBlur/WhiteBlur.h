//
//  WhiteBlur.h
//  Sileo
//
//  Created by Kabir Oberai on 10/09/18.
//  Copyright © 2018 CoolStar. All rights reserved.
//

#define WHITE_BLUR_TAG ((long)0x70757265)
// Preserve the native thin material only inside Ning's new dock surface.
#define THEMEBOARD_DOCK_BLUR_TAG ((long)0x5442444B)

@interface UIView (Hairline)

@property (nonatomic, assign, getter=_hidesShadow, setter=_setHidesShadow:) BOOL hidesShadow;

@end

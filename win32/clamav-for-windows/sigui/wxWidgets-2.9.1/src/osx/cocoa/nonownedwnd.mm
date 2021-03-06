/////////////////////////////////////////////////////////////////////////////
// Name:        src/osx/cocoa/nonownedwnd.mm
// Purpose:     non owned window for cocoa
// Author:      DavidStefan Csomor
// Modified by:
// Created:     2008-06-20
// RCS-ID:      $Id: nonownedwnd.mm 48805 2007-09-19 14:52:25Z SC $
// Copyright:   (c) Stefan Csomor
// Licence:     wxWindows licence
/////////////////////////////////////////////////////////////////////////////

#include "wx/wxprec.h"
#ifndef WX_PRECOMP
    #include "wx/nonownedwnd.h"
    #include "wx/frame.h"
    #include "wx/app.h"
#endif

#include "wx/osx/private.h"

NSRect wxToNSRect( NSView* parent, const wxRect& r )
{
    NSRect frame = parent ? [parent bounds] : [[NSScreen mainScreen] frame];
    int y = r.y;
    int x = r.x ;
    if ( parent == NULL || ![ parent isFlipped ] )
        y = (int)(frame.size.height - ( r.y + r.height ));
    return NSMakeRect(x, y, r.width , r.height);
}

wxRect wxFromNSRect( NSView* parent, const NSRect& rect )
{
    NSRect frame = parent ? [parent bounds] : [[NSScreen mainScreen] frame];
    int y = (int)rect.origin.y;
    int x = (int)rect.origin.x;
    if ( parent == NULL || ![ parent isFlipped ] )
        y = (int)(frame.size.height - (rect.origin.y + rect.size.height));
    return wxRect( x, y, (int)rect.size.width, (int)rect.size.height );
}

NSPoint wxToNSPoint( NSView* parent, const wxPoint& p )
{
    NSRect frame = parent ? [parent bounds] : [[NSScreen mainScreen] frame];
    int x = p.x ;
    int y = p.y;
    if ( parent == NULL || ![ parent isFlipped ] )
        y = (int)(frame.size.height - ( p.y ));
    return NSMakePoint(x, y);
}

wxPoint wxFromNSPoint( NSView* parent, const NSPoint& p )
{
    NSRect frame = parent ? [parent bounds] : [[NSScreen mainScreen] frame];
    int x = (int)p.x;
    int y = (int)p.y;
    if ( parent == NULL || ![ parent isFlipped ] )
        y = (int)(frame.size.height - ( p.y ));
    return wxPoint( x, y);
}

bool shouldHandleSelector(SEL selector)
{
    if (selector == @selector(noop:)
            || selector == @selector(complete:)
            || selector == @selector(deleteBackward:)
            || selector == @selector(deleteForward:)
            || selector == @selector(insertNewline:)
            || selector == @selector(insertTab:)
            || selector == @selector(keyDown:)
            || selector == @selector(keyUp:)
            || selector == @selector(scrollPageUp:)
            || selector == @selector(scrollPageDown:)
            || selector == @selector(scrollToBeginningOfDocument:)
            || selector == @selector(scrollToEndOfDocument:))
        return false;

    return true;

}

//
// wx category for NSWindow (our own and wrapped instances)
//

@interface NSWindow (wxNSWindowSupport)

- (wxNonOwnedWindowCocoaImpl*) WX_implementation;

- (bool) WX_filterSendEvent:(NSEvent *) event;

@end

@implementation NSWindow (wxNSWindowSupport)

- (wxNonOwnedWindowCocoaImpl*) WX_implementation
{
    return (wxNonOwnedWindowCocoaImpl*) wxNonOwnedWindowImpl::FindFromWXWindow( self );
}

// TODO in cocoa everything during a drag is sent to the NSWindow the mouse down occured, 
// this does not conform to the wx behaviour if the window is not captured, so try to resend
// or capture all wx mouse event handling at the tlw as we did for carbon

- (bool) WX_filterSendEvent:(NSEvent *) event
{
    bool handled = false;
    if ( ([event type] >= NSLeftMouseDown) && ([event type] <= NSMouseExited) )
    {
        wxWindow* cw = wxWindow::GetCapture();
        if ( cw != NULL )
        {
            ((wxWidgetCocoaImpl*)cw->GetPeer())->DoHandleMouseEvent( event);
            handled = true;
        }
    }
    return handled;
}
@end

//
// wx native implementation 
//

@interface wxNSWindow : NSWindow
{
}

- (void) sendEvent:(NSEvent *)event;
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen;
- (void)noResponderFor: (SEL) selector;
@end

@implementation wxNSWindow

- (void)sendEvent:(NSEvent *) event
{
    if ( ![self WX_filterSendEvent: event] )
    {
        WXEVENTREF formerEvent = wxTheApp == NULL ? NULL : wxTheApp->MacGetCurrentEvent();
        WXEVENTHANDLERCALLREF formerHandler = wxTheApp == NULL ? NULL : wxTheApp->MacGetCurrentEventHandlerCallRef();

        if (wxTheApp)
            wxTheApp->MacSetCurrentEvent(event, NULL);

        [super sendEvent: event];

        if (wxTheApp)
            wxTheApp->MacSetCurrentEvent(formerEvent , formerHandler);
    }
}

// The default implementation always moves the window back onto the screen,
// even when the programmer explicitly wants to hide it.
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
    wxUnusedVar(screen);
    return frameRect;
}

- (void)doCommandBySelector:(SEL)selector
{
    if (shouldHandleSelector(selector) &&
        !(selector == @selector(cancel:) || selector == @selector(cancelOperation:)) )
        [super doCommandBySelector:selector];
}


// NB: if we don't do this, all key downs that get handled lead to a NSBeep
- (void)noResponderFor: (SEL) selector
{
    if (selector != @selector(keyDown:) && selector != @selector(keyUp:))
    {
        [super noResponderFor:selector];
    }
}

// We need this for borderless windows, i.e. shaped windows or windows without  
// a title bar. For more info, see:
// http://lists.apple.com/archives/cocoa-dev/2008/May/msg02091.html
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

@end

@interface wxNSPanel : NSPanel
{
}

- (void)noResponderFor: (SEL) selector;
- (void)sendEvent:(NSEvent *)event;
@end

@implementation wxNSPanel

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)doCommandBySelector:(SEL)selector
{
    if (shouldHandleSelector(selector))
        [super doCommandBySelector:selector];
}

// NB: if we don't do this, it seems that all events that end here lead to a NSBeep
- (void)noResponderFor: (SEL) selector
{
    if (selector != @selector(keyDown:) && selector != @selector(keyUp:))
    {
        [super noResponderFor:selector];
    }
}

- (void)sendEvent:(NSEvent *) event
{
    if ( ![self WX_filterSendEvent: event] )
        [super sendEvent: event];
}

@end


//
// controller
//

@interface wxNonOwnedWindowController : NSObject wxOSX_10_6_AND_LATER(<NSWindowDelegate>)
{
}

- (void)windowDidResize:(NSNotification *)notification;
- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize;
- (void)windowDidResignKey:(NSNotification *)notification;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (void)windowDidMove:(NSNotification *)notification;
- (BOOL)windowShouldClose:(id)window;
- (BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)newFrame;

@end

@implementation wxNonOwnedWindowController

- (id) init
{
    [super init];
    return self;
}

- (BOOL)windowShouldClose:(id)nwindow
{
    wxNonOwnedWindowCocoaImpl* windowimpl = [(NSWindow*) nwindow WX_implementation];
    if ( windowimpl )
    {
        wxNonOwnedWindow* wxpeer = windowimpl->GetWXPeer();
        if ( wxpeer )
            wxpeer->Close();
    }
    return NO;
}

- (NSSize)windowWillResize:(NSWindow *)window
                    toSize:(NSSize)proposedFrameSize
{
    NSRect frame = [window frame];
    wxRect wxframe = wxFromNSRect( NULL, frame );
    wxframe.SetWidth( (int)proposedFrameSize.width );
    wxframe.SetHeight( (int)proposedFrameSize.height );

    wxNonOwnedWindowCocoaImpl* windowimpl = [window WX_implementation];
    if ( windowimpl )
    {
        wxNonOwnedWindow* wxpeer = windowimpl->GetWXPeer();
        if ( wxpeer )
        {
            wxpeer->HandleResizing( 0, &wxframe );
            NSSize newSize = NSMakeSize(wxframe.GetWidth(), wxframe.GetHeight());
            return newSize;
        }
    }

    return proposedFrameSize;
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow* window = (NSWindow*) [notification object];
    wxNonOwnedWindowCocoaImpl* windowimpl = [window WX_implementation];
    if ( windowimpl )
    {
        wxNonOwnedWindow* wxpeer = windowimpl->GetWXPeer();
        if ( wxpeer )
            wxpeer->HandleResized(0);
    }
}

- (void)windowDidMove:(NSNotification *)notification
{
    wxNSWindow* window = (wxNSWindow*) [notification object];
    wxNonOwnedWindowCocoaImpl* windowimpl = [window WX_implementation];
    if ( windowimpl )
    {
        wxNonOwnedWindow* wxpeer = windowimpl->GetWXPeer();
        if ( wxpeer )
            wxpeer->HandleMoved(0);
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    NSWindow* window = (NSWindow*) [notification object];
    wxNonOwnedWindowCocoaImpl* windowimpl = [window WX_implementation];
    if ( windowimpl )
    {
        wxNonOwnedWindow* wxpeer = windowimpl->GetWXPeer();
        if ( wxpeer )
            wxpeer->HandleActivated(0, true);
    }
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    NSWindow* window = (NSWindow*) [notification object];
    wxNonOwnedWindowCocoaImpl* windowimpl = [window WX_implementation];
    if ( windowimpl )
    {
        wxNonOwnedWindow* wxpeer = windowimpl->GetWXPeer();
        if ( wxpeer )
        {
            wxpeer->HandleActivated(0, false);
            // Needed for popup window since the firstResponder
            // (focus in wx) doesn't change when this
            // TLW becomes inactive.
            wxFocusEvent event( wxEVT_KILL_FOCUS, wxpeer->GetId());
            event.SetEventObject(wxpeer);
            wxpeer->HandleWindowEvent(event);
        }
    }
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)anObject
{
    wxUnusedVar(sender);

    if ([anObject isKindOfClass:[wxNSTextField class]])
    {
        wxNSTextField* tf = (wxNSTextField*) anObject;
        wxNSTextFieldEditor* editor = [tf fieldEditor];
        if ( editor == nil )
        {
            editor = [[wxNSTextFieldEditor alloc] init];
            [editor setFieldEditor:YES];
            [tf setFieldEditor:editor];
        }
        return editor;
    }

    return nil;
}

- (BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)newFrame
{
    wxUnusedVar(newFrame);
    wxNonOwnedWindowCocoaImpl* windowimpl = [window WX_implementation];
    if ( windowimpl )
    {
        wxNonOwnedWindow* wxpeer = windowimpl->GetWXPeer();
        wxMaximizeEvent event(wxpeer->GetId());
        event.SetEventObject(wxpeer);
        return !wxpeer->HandleWindowEvent(event);
    }
    return true;
}

@end

IMPLEMENT_DYNAMIC_CLASS( wxNonOwnedWindowCocoaImpl , wxNonOwnedWindowImpl )

wxNonOwnedWindowCocoaImpl::wxNonOwnedWindowCocoaImpl( wxNonOwnedWindow* nonownedwnd) :
    wxNonOwnedWindowImpl(nonownedwnd)
{
    m_macWindow = NULL;
    m_macFullScreenData = NULL;
}

wxNonOwnedWindowCocoaImpl::wxNonOwnedWindowCocoaImpl()
{
    m_macWindow = NULL;
    m_macFullScreenData = NULL;
}

wxNonOwnedWindowCocoaImpl::~wxNonOwnedWindowCocoaImpl()
{
    if ( !m_wxPeer->IsNativeWindowWrapper() )
    {
        [m_macWindow setDelegate:nil];
        [m_macWindow release];
    }
}

void wxNonOwnedWindowCocoaImpl::WillBeDestroyed()
{
    if ( !m_wxPeer->IsNativeWindowWrapper() )
    {
        [m_macWindow setDelegate:nil];
    }
}

void wxNonOwnedWindowCocoaImpl::Create( wxWindow* WXUNUSED(parent), const wxPoint& pos, const wxSize& size,
long style, long extraStyle, const wxString& WXUNUSED(name) )
{
    static wxNonOwnedWindowController* controller = NULL;

    if ( !controller )
        controller =[[wxNonOwnedWindowController alloc] init];


    int windowstyle = NSBorderlessWindowMask;

    if ( style & wxFRAME_TOOL_WINDOW || ( style & wxPOPUP_WINDOW ) ||
            GetWXPeer()->GetExtraStyle() & wxTOPLEVEL_EX_DIALOG )
    {
        m_macWindow = [wxNSPanel alloc];
    }
    else
        m_macWindow = [wxNSWindow alloc];

    CGWindowLevel level = kCGNormalWindowLevel;

    if ( style & wxFRAME_TOOL_WINDOW )
    {
        windowstyle |= NSUtilityWindowMask;
        if ( ( style & wxMINIMIZE_BOX ) || ( style & wxMAXIMIZE_BOX ) ||
            ( style & wxCLOSE_BOX ) || ( style & wxSYSTEM_MENU ) )
        {
            windowstyle |= NSTitledWindowMask ;
        }
    }
    else if ( ( style & wxPOPUP_WINDOW ) )
    {
        level = kCGPopUpMenuWindowLevel;
        /*
        if ( ( style & wxBORDER_NONE ) )
        {
            wclass = kHelpWindowClass ;   // has no border
            attr |= kWindowNoShadowAttribute;
        }
        else
        {
            wclass = kPlainWindowClass ;  // has a single line border, it will have to do for now
        }
        */
    }
    else if ( ( style & wxCAPTION ) )
    {
        windowstyle |= NSTitledWindowMask ;
    }
    else if ( ( style & wxFRAME_DRAWER ) )
    {
        /*
        wclass = kDrawerWindowClass;
        */
    }
    else
    {
        // set these even if we have no title, otherwise the controls won't be visible
        if ( ( style & wxMINIMIZE_BOX ) || ( style & wxMAXIMIZE_BOX ) ||
            ( style & wxCLOSE_BOX ) || ( style & wxSYSTEM_MENU ) )
        {
            windowstyle |= NSTitledWindowMask ;
        }
        /*
        else if ( ( style & wxNO_BORDER ) )
        {
            wclass = kSimpleWindowClass ;
        }
        else
        {
            wclass = kPlainWindowClass ;
        }
        */
    }

    if ( windowstyle & NSTitledWindowMask )
    {
        if ( ( style & wxMINIMIZE_BOX ) )
            windowstyle |= NSMiniaturizableWindowMask ;

        if ( ( style & wxMAXIMIZE_BOX ) )
            windowstyle |= NSResizableWindowMask ; // TODO showing ZOOM ?

        if ( ( style & wxRESIZE_BORDER ) )
            windowstyle |= NSResizableWindowMask ;

        if ( ( style & wxCLOSE_BOX) )
            windowstyle |= NSClosableWindowMask ;
    }
    if ( extraStyle & wxFRAME_EX_METAL)
        windowstyle |= NSTexturedBackgroundWindowMask;

    if ( ( style & wxFRAME_FLOAT_ON_PARENT ) || ( style & wxFRAME_TOOL_WINDOW ) )
        level = kCGFloatingWindowLevel;

    if ( ( style & wxSTAY_ON_TOP ) )
        level = kCGUtilityWindowLevel;

    NSRect r = wxToNSRect( NULL, wxRect( pos, size) );

    r = [NSWindow contentRectForFrameRect:r styleMask:windowstyle];

    [m_macWindow initWithContentRect:r
        styleMask:windowstyle
        backing:NSBackingStoreBuffered
        defer:NO
        ];

    [m_macWindow setLevel:level];

    [m_macWindow setDelegate:controller];

    [m_macWindow setAcceptsMouseMovedEvents: YES];
    
    if ( ( style & wxFRAME_SHAPED) )
    {
        [m_macWindow setOpaque:NO];
        [m_macWindow setAlphaValue:1.0];
    }
    
    if ( !(style & wxFRAME_TOOL_WINDOW) )
        [m_macWindow setHidesOnDeactivate:NO];
}

void wxNonOwnedWindowCocoaImpl::Create( wxWindow* WXUNUSED(parent), WXWindow nativeWindow )
{
    m_macWindow = nativeWindow;
}

WXWindow wxNonOwnedWindowCocoaImpl::GetWXWindow() const
{
    return m_macWindow;
}

void wxNonOwnedWindowCocoaImpl::Raise()
{
    [m_macWindow orderWindow:NSWindowAbove relativeTo:0];
}

void wxNonOwnedWindowCocoaImpl::Lower()
{
    [m_macWindow orderWindow:NSWindowBelow relativeTo:0];
}

void wxNonOwnedWindowCocoaImpl::ShowWithoutActivating()
{
    [m_macWindow orderFront:nil];
    [[m_macWindow contentView] setNeedsDisplay: YES];
}

bool wxNonOwnedWindowCocoaImpl::Show(bool show)
{
    if ( show )
    {
        wxNonOwnedWindow* wxpeer = GetWXPeer(); 
        if (wxpeer && !(wxpeer->GetWindowStyle() & wxFRAME_TOOL_WINDOW)) 
            [m_macWindow makeKeyAndOrderFront:nil];
        else 
            [m_macWindow orderFront:nil]; 
        [[m_macWindow contentView] setNeedsDisplay: YES];
    }
    else
        [m_macWindow orderOut:nil];
    return true;
}

bool wxNonOwnedWindowCocoaImpl::ShowWithEffect(bool show,
                                               wxShowEffect effect,
                                               unsigned timeout)
{
    return wxWidgetCocoaImpl::
            ShowViewOrWindowWithEffect(m_wxPeer, show, effect, timeout);
}

void wxNonOwnedWindowCocoaImpl::Update()
{
    [m_macWindow displayIfNeeded];
}

bool wxNonOwnedWindowCocoaImpl::SetTransparent(wxByte alpha)
{
    [m_macWindow setAlphaValue:(CGFloat) alpha/255.0];
    return true;
}

bool wxNonOwnedWindowCocoaImpl::SetBackgroundColour(const wxColour& WXUNUSED(col) )
{
    return true;
}

void wxNonOwnedWindowCocoaImpl::SetExtraStyle( long exStyle )
{
    if ( m_macWindow )
    {
        bool metal = exStyle & wxFRAME_EX_METAL ;
        int windowStyle = [ m_macWindow styleMask];
        if ( metal && !(windowStyle & NSTexturedBackgroundWindowMask) )
        {
            wxFAIL_MSG( wxT("Metal Style cannot be changed after creation") );
        }
        else if ( !metal && (windowStyle & NSTexturedBackgroundWindowMask ) )
        {
            wxFAIL_MSG( wxT("Metal Style cannot be changed after creation") );
        }
    }
}

void wxNonOwnedWindowCocoaImpl::SetWindowStyleFlag( long style )
{
    if (m_macWindow)
    {
        CGWindowLevel level = kCGNormalWindowLevel;
        
        if (style & wxSTAY_ON_TOP)
            level = kCGUtilityWindowLevel;
        else if (( style & wxFRAME_FLOAT_ON_PARENT ) || ( style & wxFRAME_TOOL_WINDOW ))
            level = kCGFloatingWindowLevel;
        
        [m_macWindow setLevel: level];
    }
}

bool wxNonOwnedWindowCocoaImpl::SetBackgroundStyle(wxBackgroundStyle style)
{
    if ( style == wxBG_STYLE_TRANSPARENT )
    {
        [m_macWindow setOpaque:NO];
        [m_macWindow setBackgroundColor:[NSColor clearColor]];
    }

    return true;
}

bool wxNonOwnedWindowCocoaImpl::CanSetTransparent()
{
    return true;
}

void wxNonOwnedWindowCocoaImpl::MoveWindow(int x, int y, int width, int height)
{
    NSRect r = wxToNSRect( NULL, wxRect(x,y,width, height) );
    // do not trigger refreshes upon invisible and possible partly created objects
    [m_macWindow setFrame:r display:GetWXPeer()->IsShownOnScreen()];
}

void wxNonOwnedWindowCocoaImpl::GetPosition( int &x, int &y ) const
{
    wxRect r = wxFromNSRect( NULL, [m_macWindow frame] );
    x = r.GetLeft();
    y = r.GetTop();
}

void wxNonOwnedWindowCocoaImpl::GetSize( int &width, int &height ) const
{
    NSRect rect = [m_macWindow frame];
    width = (int)rect.size.width;
    height = (int)rect.size.height;
}

void wxNonOwnedWindowCocoaImpl::GetContentArea( int& left, int &top, int &width, int &height ) const
{
    NSRect outer = NSMakeRect(100,100,100,100);
    NSRect content = [NSWindow contentRectForFrameRect:outer styleMask:[m_macWindow styleMask] ];
    NSRect rect = [[m_macWindow contentView] frame];
    left = (int)rect.origin.x;
    top = (int)rect.origin.y;
    width = (int)rect.size.width;
    height = (int)rect.size.height;
}

bool wxNonOwnedWindowCocoaImpl::SetShape(const wxRegion& WXUNUSED(region))
{
    [m_macWindow setOpaque:NO];
    [m_macWindow setBackgroundColor:[NSColor clearColor]];

    return true;
}

void wxNonOwnedWindowCocoaImpl::SetTitle( const wxString& title, wxFontEncoding encoding )
{
    [m_macWindow setTitle:wxCFStringRef( title , encoding ).AsNSString()];
}

bool wxNonOwnedWindowCocoaImpl::IsMaximized() const
{
    if (([m_macWindow styleMask] & NSResizableWindowMask) != 0)
    {
        return [m_macWindow isZoomed];
    }
    else
    {
        NSRect rectScreen = [[NSScreen mainScreen] visibleFrame];
        NSRect rectWindow = [m_macWindow frame];
        return (rectScreen.origin.x == rectWindow.origin.x &&
                rectScreen.origin.y == rectWindow.origin.y &&
                rectScreen.size.width == rectWindow.size.width &&
                rectScreen.size.height == rectWindow.size.height);
    }
}

bool wxNonOwnedWindowCocoaImpl::IsIconized() const
{
    return [m_macWindow isMiniaturized];
}

void wxNonOwnedWindowCocoaImpl::Iconize( bool iconize )
{
    if ( iconize )
        [m_macWindow miniaturize:nil];
    else
        [m_macWindow deminiaturize:nil];
}

void wxNonOwnedWindowCocoaImpl::Maximize(bool WXUNUSED(maximize))
{
    [m_macWindow zoom:nil];
}


// http://cocoadevcentral.com/articles/000028.php

typedef struct
{
    int m_formerLevel;
    NSRect m_formerFrame;
} FullScreenData ;

bool wxNonOwnedWindowCocoaImpl::IsFullScreen() const
{
    return m_macFullScreenData != NULL ;
}

bool wxNonOwnedWindowCocoaImpl::ShowFullScreen(bool show, long WXUNUSED(style))
{
    if ( show )
    {
        FullScreenData *data = (FullScreenData *)m_macFullScreenData ;
        delete data ;
        data = new FullScreenData();

        m_macFullScreenData = data ;
        data->m_formerLevel = [m_macWindow level];
        data->m_formerFrame = [m_macWindow frame];
        CGDisplayCapture( kCGDirectMainDisplay );
        [m_macWindow setLevel:CGShieldingWindowLevel()];
        [m_macWindow setFrame:[[NSScreen mainScreen] frame] display:YES];
    }
    else if ( m_macFullScreenData != NULL )
    {
        FullScreenData *data = (FullScreenData *) m_macFullScreenData ;
        CGDisplayRelease( kCGDirectMainDisplay );
        [m_macWindow setLevel:data->m_formerLevel];
        [m_macWindow setFrame:data->m_formerFrame display:YES];
        delete data ;
        m_macFullScreenData = NULL ;
    }

    return true;
}

void wxNonOwnedWindowCocoaImpl::RequestUserAttention(int flagsWX)
{
    NSRequestUserAttentionType flagsOSX;
    switch ( flagsWX )
    {
        case wxUSER_ATTENTION_INFO:
            flagsOSX = NSInformationalRequest;
            break;

        case wxUSER_ATTENTION_ERROR:
            flagsOSX = NSCriticalRequest;
            break;

        default:
            wxFAIL_MSG( "invalid RequestUserAttention() flags" );
            return;
    }

    [NSApp requestUserAttention:flagsOSX];
}

void wxNonOwnedWindowCocoaImpl::ScreenToWindow( int *x, int *y )
{
    wxPoint p((x ? *x : 0), (y ? *y : 0) );
    NSPoint nspt = wxToNSPoint( NULL, p );
    nspt = [m_macWindow convertScreenToBase:nspt];
    nspt = [[m_macWindow contentView] convertPoint:nspt fromView:nil];
    p = wxFromNSPoint([m_macWindow contentView], nspt);
    if ( x )
        *x = p.x;
    if ( y )
        *y = p.y;
}

void wxNonOwnedWindowCocoaImpl::WindowToScreen( int *x, int *y )
{
    wxPoint p((x ? *x : 0), (y ? *y : 0) );
    NSPoint nspt = wxToNSPoint( [m_macWindow contentView], p );
    nspt = [[m_macWindow contentView] convertPoint:nspt toView:nil];
    nspt = [m_macWindow convertBaseToScreen:nspt];
    p = wxFromNSPoint( NULL, nspt);
    if ( x )
        *x = p.x;
    if ( y )
        *y = p.y;
}

bool wxNonOwnedWindowCocoaImpl::IsActive()
{
    return [m_macWindow isKeyWindow];
}

void wxNonOwnedWindowCocoaImpl::SetModified(bool modified)
{
    [m_macWindow setDocumentEdited:modified];
}

bool wxNonOwnedWindowCocoaImpl::IsModified() const
{
    return [m_macWindow isDocumentEdited];
}

wxNonOwnedWindowImpl* wxNonOwnedWindowImpl::CreateNonOwnedWindow( wxNonOwnedWindow* wxpeer, wxWindow* parent, WXWindow nativeWindow)
{
    wxNonOwnedWindowCocoaImpl* now = new wxNonOwnedWindowCocoaImpl( wxpeer );
    now->Create( parent, nativeWindow );
    return now;
}

wxNonOwnedWindowImpl* wxNonOwnedWindowImpl::CreateNonOwnedWindow( wxNonOwnedWindow* wxpeer, wxWindow* parent, const wxPoint& pos, const wxSize& size,
    long style, long extraStyle, const wxString& name )
{
    wxNonOwnedWindowImpl* now = new wxNonOwnedWindowCocoaImpl( wxpeer );
    now->Create( parent, pos, size, style , extraStyle, name );
    return now;
}

#define CP_ALLOW_PRIVATE_ACCESS
#import "ViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "AppDelegate.h"
#import "ShowcaseDemo.h"
#import "PolyRenderer.h"

#define SLIDE_ANIMATION_DURATION 0.25
#define TITLE_ANIMATION_DURATION 0.15

#define MIN_TIMESCALE (1.0/64.0)
#define MAX_TIMESCALE 1.0

#define MIN_TIMESTEP (1.0/240.0)
#define MAX_TIMESTEP (1.0/15.0)

#define MAX_ITERATIONS 30

#define STAT_DELAY 1.0


static cpFloat
LogSliderToValue(cpFloat min, cpFloat max, cpFloat value)
{
	return min*cpfpow(max/min, value);
}

static cpFloat
ValueToLogSlider(cpFloat min, cpFloat max, cpFloat value)
{
	return logf(value/min)/logf(max/min);
}


@interface ShowcaseGLView : GLKView

@property(nonatomic, assign) id touchesDelegate;

@end


@implementation ShowcaseGLView

@synthesize touchesDelegate = _touchesDelegate;

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
	[_touchesDelegate touchesBegan:touches withEvent:event];
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
	[_touchesDelegate touchesMoved:touches withEvent:event];
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
	[_touchesDelegate touchesEnded:touches withEvent:event];
}

-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
	[_touchesDelegate touchesCancelled:touches withEvent:event];
}

@end


@interface ViewController(){
	ShowcaseDemo *_demo;
	
	EAGLContext *_context;
	PolyRenderer *_staticRenderer;
	PolyRenderer *_renderer;
	
	IBOutlet GLKViewController *_glkViewController;
	
	IBOutlet UILabel *_demoLabel;
	
	IBOutlet UIView *_tray;
	
	IBOutlet UISlider *_timeScaleSlider;
	IBOutlet UILabel *_timeScaleLabel;
	
	IBOutlet UISlider *_timeStepSlider;
	IBOutlet UILabel *_timeStepLabel;
	
	IBOutlet UISlider *_iterationsSlider;
	IBOutlet UILabel *_iterationsLabel;
	
	NSTimer *_statsTimer;
	IBOutlet UITextView *_statsView;
	int _physicsTicks, _renderTicks;
}

@property(nonatomic, readonly) ShowcaseGLView *glView;

@property(nonatomic, assign) BOOL isTrayOpen;

-(void)setupGL;

@end



@implementation ViewController

-(ShowcaseGLView *)glView
{
	return (ShowcaseGLView *)[_glkViewController view];
}

-(id)initWithDemoClassName:(NSString *)demo
{
	NSString *nib_name = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone ? @"ViewController_iPhone" : @"ViewController_iPad");
	if((self = [super initWithNibName:nib_name bundle:nil])){
//	if((self = [super init])){
		_demo = [[NSClassFromString(demo) alloc] init];
	}
	
	return self;
}

//MARK: Actions

@synthesize isTrayOpen = _isTrayOpen;
-(void)setIsTrayOpen:(BOOL)isTrayOpen
{
	if(isTrayOpen && !_isTrayOpen){
		_tray.hidden = FALSE;
		[self.glView setUserInteractionEnabled:FALSE];
//		_glkViewController.paused = TRUE;
		
		[UIView animateWithDuration:SLIDE_ANIMATION_DURATION animations:^{
			[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
			
			CGRect frame = self.view.bounds;
			frame.origin.x -= _tray.frame.size.width;
			
			self.glView.frame = frame;
		}];
	} else if(!isTrayOpen && _isTrayOpen){
		[UIView animateWithDuration:SLIDE_ANIMATION_DURATION animations:^{
			[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
			self.glView.frame = self.view.bounds;
		} completion:^(BOOL finished){
			if(finished){
				_tray.hidden = TRUE;
				[self.glView setUserInteractionEnabled:TRUE];
//				_glkViewController.paused = FALSE;
			}
		}];
	}
	
	_isTrayOpen = isTrayOpen;
}

-(void)swipeLeft;
{
	self.isTrayOpen = TRUE;
}

-(void)swipeRight;
{
	if(self.isTrayOpen){
		self.isTrayOpen = FALSE;
	} else {
		[CATransaction begin]; {
			[self.view addSubview:[[UIImageView alloc] initWithImage:self.glView.snapshot]];
			[self.glView removeFromSuperview];
		}; [CATransaction commit];
		
		[(AppDelegate *)[UIApplication sharedApplication].delegate nextDemo];
	}
}

-(IBAction)framerate:(UISwitch *)toggle;
{
	_glkViewController.preferredFramesPerSecond = (toggle.on ? 30 : 60);
}

-(IBAction)timeScale:(UISlider *)slider
{
	cpFloat value = LogSliderToValue(MIN_TIMESCALE, MAX_TIMESCALE, slider.value);
	_demo.timeScale = value;
	_timeScaleLabel.text = [NSString stringWithFormat:@"Time Scale: 1:%.2f", 1.0/value];
}

-(IBAction)timeStep:(UISlider *)slider
{
	cpFloat value = LogSliderToValue(MIN_TIMESTEP, MAX_TIMESTEP, slider.value);
	_demo.timeStep = value;
	_timeStepLabel.text = [NSString stringWithFormat:@"Time Step: 1:%.2f", 1.0/value];
}

-(IBAction)iterations:(UISlider *)slider
{
	int value = slider.value;
	_demo.space.iterations = value;
	_iterationsLabel.text = [NSString stringWithFormat:@"Iterations: %d", value];
}

-(IBAction)reset;
{
	_demo = [[[_demo class] alloc] init];
	
	// Pump the slider data
	[self timeScale:_timeScaleSlider];
	[self timeStep:_timeStepSlider];
	[self iterations:_iterationsSlider];
	
	_physicsTicks = 0;
	_renderTicks = 0;
	
	self.glView.touchesDelegate = _demo;
	
	[self setupGL];
}

-(void)updateStats:(NSTimer *)timer
{
	cpSpace *space = _demo.space.space;
	
	// Dig out these numbers using the private API to avoid generating full lists.
	NSUInteger bodies = space->bodies->num;
	NSUInteger activeShapes = cpSpatialIndexCount(space->activeShapes);
	NSUInteger staticShapes = activeShapes + cpSpatialIndexCount(space->staticShapes);
	NSUInteger constraints = space->constraints->num;
	NSUInteger contacts = space->arbiters->num;
	
	float duration = -[(NSDate *)[timer userInfo] timeIntervalSinceNow];
	float physics = (_demo.ticks - _physicsTicks)/duration;
	float render = _renderTicks/duration;
	
	_statsView.text = [NSString stringWithFormat:
		@"Bodies: %d\n"
		@"Shapes: %d (%d)\n"
		@"Constraints: %d\n"
		@"Contacts: %d\n"
		@"Physics: %.1f Hz\n"
		@"Render: %.1f Hz\n",
		bodies, activeShapes, staticShapes, constraints, contacts, physics, render
	];
	
	_physicsTicks = _demo.ticks;
	_renderTicks = 0;
	
	[_statsTimer invalidate];
	_statsTimer = [NSTimer scheduledTimerWithTimeInterval:STAT_DELAY target:self selector:@selector(updateStats:) userInfo:[NSDate date] repeats:FALSE];
}

//MARK: Load/Unload

-(void)setupGL
{
	[EAGLContext setCurrentContext:_context];

	GLfloat clear = 1.0;
	glClearColor(clear, clear, clear, 1.0);

	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
	
	CGSize viewSize = self.glView.bounds.size;
	Transform proj = t_mult(t_scale((viewSize.height/viewSize.width)*(4.0/3.0), 1.0), t_ortho(cpBBNew(-320, -240, 320, 240)));
	_demo.touchTransform = t_mult(t_inverse(proj), t_ortho(cpBBNew(0, viewSize.height, viewSize.width, 0)));
	
	_staticRenderer = [[PolyRenderer alloc] initWithProjection:proj];
	_renderer = [[PolyRenderer alloc] initWithProjection:proj];
		
	[_demo prepareStaticRenderer:_staticRenderer];
	[_staticRenderer prepareStatic];
}

- (void)tearDownGL
{
	NSLog(@"Tearing down GL");
	[EAGLContext setCurrentContext:_context];
	
	_staticRenderer = nil;
	_renderer = nil;

	_context = nil;
	[EAGLContext setCurrentContext:nil];
}

-(void)fadeLabel
{
	[UIView animateWithDuration:TITLE_ANIMATION_DURATION animations:^{
		_demoLabel.alpha = 0.0;
	} completion:^(BOOL completed){
		[_demoLabel removeFromSuperview];
	}];
}

-(void)viewDidLoad
{
	[super viewDidLoad];
	
	if(_demo.name){
		_demoLabel.text = _demo.name;
		[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(fadeLabel) userInfo:nil repeats:NO];		
	} else {
		[_demoLabel removeFromSuperview];
	}
	
	// Set sliders to their default values
	_timeScaleSlider.value = ValueToLogSlider(MIN_TIMESCALE, MAX_TIMESCALE, 1.0);
	_timeStepSlider.value = ValueToLogSlider(MIN_TIMESTEP, MAX_TIMESTEP, _demo.timeStep);
	_iterationsSlider.value = _demo.space.iterations;
	[self timeScale:_timeScaleSlider];
	[self timeStep:_timeStepSlider];
	[self iterations:_iterationsSlider];
	
	_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
	NSAssert(_context, @"Failed to create ES context");
	
	[self.view insertSubview:self.glView belowSubview:_demoLabel];
//	[self.view addSubview:self.glView];
	self.glView.context = _context;
	self.glView.touchesDelegate = _demo;
	
	// Add a nice shadow.
	self.glView.layer.shadowColor = [UIColor blackColor].CGColor;
	self.glView.layer.shadowOpacity = 1.0f;
	self.glView.layer.shadowOffset = CGSizeZero;
	self.glView.layer.shadowRadius = 15.0;
	self.glView.layer.masksToBounds = NO;
	self.glView.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.glView.bounds].CGPath;
	
	// Got weird threading crashes when these were added in a nib.
	{
		UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
		swipe.direction = UISwipeGestureRecognizerDirectionLeft;
		swipe.numberOfTouchesRequired = 3;
		[self.view addGestureRecognizer:swipe];
	}{
		UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
		swipe.direction = UISwipeGestureRecognizerDirectionRight;
		swipe.numberOfTouchesRequired = 3;
		[self.view addGestureRecognizer:swipe];
	}{
//		UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp)];
//		swipe.direction = UISwipeGestureRecognizerDirectionUp;
//		swipe.numberOfTouchesRequired = 3;
//		[self.view addGestureRecognizer:swipe];
//	}{
//		UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown)];
//		swipe.direction = UISwipeGestureRecognizerDirectionDown;
//		swipe.numberOfTouchesRequired = 3;
//		[self.view addGestureRecognizer:swipe];
	}
	
	// TODO add down swipe for an info pane?

	[self setupGL];
	
	_statsTimer = [NSTimer scheduledTimerWithTimeInterval:STAT_DELAY target:self selector:@selector(updateStats:) userInfo:[NSDate date] repeats:FALSE];
}

-(void)viewDidUnload
{    
	[super viewDidUnload];
	[self tearDownGL];
	
	[_statsTimer invalidate];
	_statsTimer = nil;
}

-(void)dealloc
{
	[self tearDownGL];
}

//MARK: Rotation

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return interfaceOrientation == UIInterfaceOrientationLandscapeRight;
}

//MARK: GLKView and GLKViewController delegate methods

-(void)glkViewControllerUpdate:(GLKViewController *)controller
{
	[_demo update:_glkViewController.timeSinceLastUpdate];
}

-(void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
	NSAssert([EAGLContext currentContext] == _context, @"Wrong context set?");
	glClear(GL_COLOR_BUFFER_BIT);
	
	[_staticRenderer renderStatic];
	
	[_demo render:_renderer];
	[_renderer render];
	
	_renderTicks++;
	PRINT_GL_ERRORS();
}

@end

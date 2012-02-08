#import "ShowcaseDemo.h"

@interface PlanetDemo : ShowcaseDemo @end
@implementation PlanetDemo {
	ChipmunkBody *_planetBody;
}

-(NSString *)name
{
	return @"Planet";
}

static const cpFloat gravityStrength = 5.0e6f;

static void
PlanetGravityVelocityFunc(cpBody *body, cpVect gravity, cpFloat damping, cpFloat dt)
{
	// Gravitational acceleration is proportional to the inverse square of
	// distance, and directed toward the origin. The central planet is assumed
	// to be massive enough that it affects the satellites but not vice versa.
	cpVect pos = cpBodyGetPos(body);
	cpFloat sqdist = cpvlengthsq(pos);
	cpVect g = cpvmult(pos, -gravityStrength/(sqdist*cpfsqrt(sqdist)));
	
	cpBodyUpdateVelocity(body, g, damping, dt);
}

static cpVect
rand_pos(cpFloat radius)
{
	cpVect v;
	do {
		v = cpv(frand()*(640 - 2*radius) - (320 - radius), frand()*(480 - 2*radius) - (240 - radius));
	} while(cpvlength(v) < 85.0f);
	
	return v;
}

-(void)addBox
{
	const cpFloat size = 20.0f;
	const cpFloat mass = 1.0f;
	
	cpFloat radius = cpvlength(cpv(size, size));
	cpVect pos = rand_pos(radius);
	
	ChipmunkBody *body = [self.space add:[ChipmunkBody bodyWithMass:mass andMoment:cpMomentForBox(mass, size, size)]];
	body.body->velocity_func = PlanetGravityVelocityFunc;
	body.pos = pos;
	
	// Set the box's velocity to put it into a circular orbit from its
	// starting position.
	cpFloat r = cpvlength(pos);
	cpFloat v = cpfsqrt(gravityStrength/r)/r;
	body.vel = cpvmult(cpvperp(pos), v);
	
	// Set the box's angular velocity to match its orbital period and
	// align its initial angle with its position.
	body.angVel = v;
	body.angle = cpfatan2(pos.y, pos.x);
	
	ChipmunkShape *shape = [self.space add:[ChipmunkPolyShape boxWithBody:body width:size height:size]];
	shape.elasticity = 0.0f;
	shape.friction = 0.7f;
}

-(void)setup
{
	// Create a rouge body to control the planet manually.
	_planetBody = [ChipmunkBody bodyWithMass:INFINITY andMoment:INFINITY];
	_planetBody.angVel = 0.2f;
	
	for(int i=0; i<30; i++) [self addBox];
	
	ChipmunkShape *shape = [self.space add:[ChipmunkCircleShape circleWithBody:_planetBody radius:70.0f offset:cpvzero]];
	shape.elasticity = 1.0f;
	shape.friction = 1.0f;
	shape.layers = NOT_GRABABLE_MASK;
}

@end

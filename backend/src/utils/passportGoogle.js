import passport from 'passport';
import { Strategy as GoogleStrategy } from 'passport-google-oauth20';
import dotenv from 'dotenv';

dotenv.config();

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const GOOGLE_CALLBACK_URL = process.env.GOOGLE_CALLBACK_URL;

const hasGoogleOAuthConfig = Boolean(
    GOOGLE_CLIENT_ID && GOOGLE_CLIENT_SECRET && GOOGLE_CALLBACK_URL
);

passport.serializeUser((user, done) => {
    done(null, user);
});

passport.deserializeUser((user, done) => {
    done(null, user);
});

if (hasGoogleOAuthConfig) {
    passport.use(new GoogleStrategy({
        clientID: GOOGLE_CLIENT_ID,
        clientSecret: GOOGLE_CLIENT_SECRET,
        callbackURL: GOOGLE_CALLBACK_URL,
    },
        (accessToken, refreshToken, profile, done) => {
            // Ici, on peut stocker/mettre à jour l'utilisateur en base si besoin
            return done(null, {
                id: profile.id,
                displayName: profile.displayName,
                email: profile.emails?.[0]?.value,
                photo: profile.photos?.[0]?.value,
                provider: 'google',
            });
        }
    ));
} else if (process.env.NODE_ENV !== 'test') {
    console.warn('Google OAuth désactivé: variables GOOGLE_CLIENT_ID/SECRET/CALLBACK_URL manquantes.');
}

export function isGoogleOAuthEnabled() {
    return hasGoogleOAuthConfig;
}

export default passport;

//+------------------------------------------------------------------+
//| FPF_Engine.mqh                                                     |
//| Fractal Personality Field Engine with RK4 Integration             |
//| Implements J(P) = S + A (Symmetric + Antisymmetric coupling)      |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Fractal Personality Field Class                                    |
//+------------------------------------------------------------------+
class FractalPersonalityField
{
public:
   // Field indices
   enum E_PIndex { 
      P_COH = 0,    // Coherence
      P_ALIGN = 1,  // Alignment
      P_S = 2,      // Symmetric (resonance)
      P_A = 3,      // Antisymmetric (orbital/rotation)
      P_MEM = 4,    // Memory
      P_EXP = 5     // Expansion
   };
   
   #define P_DIM 6
   
   // State vector
   double P[6];
   
   // Base coupling matrix (plastic, updated via learning)
   double J_base[6][6];
   
   // Parameters for J(P) generation
   double alpha, beta, gamma, kappa, lambda;
   double delta, omega, phi, eta;
   
   // Forcing and dynamics
   double forcing_coh, forcing_align, forcing_s, forcing_a, forcing_mem, forcing_exp;
   double dissipation;
   double noise_scale;
   double maxP;
   
   // Plasticity
   double plasticity_lr;
   double plasticity_decay;
   
   // RK4 integration
   double dt_default;
   
   // Settings
   bool debugLog;
   bool plotLabels;
   string chartTag;

private:
   double J[6][6];  // Current coupling matrix
   double tempP[6];     // Temporary state for calculations
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                        |
   //+------------------------------------------------------------------+
   FractalPersonalityField()
   {
      // Initialize parameters (optimized values)
      alpha = 0.5;
      beta = 1.0;
      gamma = 0.6;
      kappa = 0.12;
      lambda = 0.8;
      
      delta = 0.35;
      omega = 1.2;
      phi = 0.7;
      eta = 0.45;
      
      // Forcing weights
      forcing_coh = 0.8;
      forcing_align = 0.6;
      forcing_s = 1.0;
      forcing_a = -0.5;
      forcing_mem = 0.3;
      forcing_exp = 0.4;
      
      dissipation = 0.15;
      noise_scale = 0.02;
      maxP = 5.0;
      
      plasticity_lr = 0.005;
      plasticity_decay = 0.998;
      
      dt_default = 1.0;
      
      debugLog = false;
      plotLabels = false;
      chartTag = "FPF_";
   }
   
   //+------------------------------------------------------------------+
   //| Initialize the field                                              |
   //+------------------------------------------------------------------+
   void Init()
   {
      // Initialize P with small random values
      for(int i = 0; i < 6; i++)
      {
         P[i] = (MathRand() / 32767.0 - 0.5) * 0.1;
      }
      
      // Initialize J_base as weak identity + small coupling
      for(int i = 0; i < 6; i++)
      {
         for(int j = 0; j < 6; j++)
         {
            if(i == j)
               J_base[i][j] = 0.5;
            else
               J_base[i][j] = (MathRand() / 32767.0 - 0.5) * 0.05;
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Generate Coupling Matrix J(P)                                     |
   //+------------------------------------------------------------------+
   void GenerateCouplingMatrix()
   {
      int n = P_DIM;
      
      // Compute mean
      double m = 0.0;
      for(int r = 0; r < n; r++) m += P[r];
      m /= (double)n;
      
      // Temporary matrices for S and A
      double S[P_DIM][P_DIM];
      double A[P_DIM][P_DIM];
      
      // Build symmetric and antisymmetric components
      for(int i = 0; i < n; i++)
      {
         for(int j = 0; j < n; j++)
         {
            int dij = MathAbs(i - j);
            double avg = 0.5 * (P[i] + P[j]);
            double diff = P[i] - P[j];
            
            // Symmetric component (resonance, coherence)
            double cosTerm = MathCos(beta * diff);
            double attenuation = MathExp(-gamma * dij);
            double normalization = 1.0 + lambda * (MathAbs(P[i]) + MathAbs(P[j])) + 1e-9;
            
            S[i][j] = alpha * avg * cosTerm * attenuation * (1.0 + kappa * m * m) / normalization;
            
            // Antisymmetric component (orbital, rotation)
            if(i == j)
            {
               A[i][j] = 0.0;
            }
            else
            {
               int k = (i + j) % n;  // Third-axis phase index
               double base = diff;
               double sinTerm = MathSin(omega * (P[i] + P[j]) + phi * P[k]);
               double attenA = MathExp(-eta * dij);
               
               A[i][j] = delta * base * sinTerm * attenA;
            }
         }
      }
      
      // Enforce symmetry for S and antisymmetry for A
      for(int i = 0; i < n; i++)
      {
         for(int j = i + 1; j < n; j++)
         {
            // Symmetrize S
            double Ssym = 0.5 * (S[i][j] + S[j][i]);
            S[i][j] = Ssym;
            S[j][i] = Ssym;
            
            // Antisymmetrize A
            double Aavg = 0.5 * (A[i][j] - A[j][i]);
            A[i][j] = Aavg;
            A[j][i] = -Aavg;
         }
      }
      
      // Combine: J = J_base + S + A
      for(int i = 0; i < n; i++)
      {
         for(int j = 0; j < n; j++)
         {
            J[i][j] = J_base[i][j] + S[i][j] + A[i][j];
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Compute derivatives dP/dt                                         |
   //+------------------------------------------------------------------+
   void ComputeDerivatives(const double &Pin[], double Ae, double An, double &dP[])
   {
      // Generate J based on current P
      for(int i = 0; i < 6; i++) tempP[i] = Pin[i];
      
      // Temporary copy for J generation
      double savedP[6];
      for(int i = 0; i < 6; i++) savedP[i] = P[i];
      for(int i = 0; i < 6; i++) P[i] = Pin[i];
      
      GenerateCouplingMatrix();
      
      // Restore
      for(int i = 0; i < 6; i++) P[i] = savedP[i];
      
      // External forcing vector
      double F[6];
      F[P_COH] = forcing_coh;
      F[P_ALIGN] = forcing_align;
      F[P_S] = forcing_s;
      F[P_A] = forcing_a;
      F[P_MEM] = forcing_mem;
      F[P_EXP] = forcing_exp;
      
      // Compute dP/dt = -kappa*P + J*P + Ae*An*F
      for(int i = 0; i < 6; i++)
      {
         double JP = 0.0;
         for(int j = 0; j < 6; j++)
         {
            JP += J[i][j] * Pin[j];
         }
         
         dP[i] = -dissipation * Pin[i] + JP + Ae * An * F[i];
      }
   }
   
   //+------------------------------------------------------------------+
   //| Update P using RK4 integration                                    |
   //+------------------------------------------------------------------+
   void UpdateP_RK4(double Ae, double An, double useDt = -1.0)
   {
      if(useDt < 0) useDt = dt_default;

      double k1[6], k2[6], k3[6], k4[6];
      double temp[6];

      // k1 = f(P)
      ComputeDerivatives(P, Ae, An, k1);

      // k2 = f(P + dt/2 * k1)
      for(int i = 0; i < 6; i++)
      {
         temp[i] = P[i] + 0.5 * useDt * k1[i];
         temp[i] = ClampVal(temp[i], -maxP, maxP);  // Clamp intermediate values
      }
      ComputeDerivatives(temp, Ae, An, k2);

      // k3 = f(P + dt/2 * k2)
      for(int i = 0; i < 6; i++)
      {
         temp[i] = P[i] + 0.5 * useDt * k2[i];
         temp[i] = ClampVal(temp[i], -maxP, maxP);  // Clamp intermediate values
      }
      ComputeDerivatives(temp, Ae, An, k3);

      // k4 = f(P + dt * k3)
      for(int i = 0; i < 6; i++)
      {
         temp[i] = P[i] + useDt * k3[i];
         temp[i] = ClampVal(temp[i], -maxP, maxP);  // Clamp intermediate values
      }
      ComputeDerivatives(temp, Ae, An, k4);

      // Update: P = P + dt/6 * (k1 + 2*k2 + 2*k3 + k4)
      for(int i = 0; i < 6; i++)
      {
         P[i] = P[i] + (useDt / 6.0) * (k1[i] + 2.0*k2[i] + 2.0*k3[i] + k4[i]);

         // Clamp to prevent explosion
         P[i] = ClampVal(P[i], -maxP, maxP);

         // Check for NaN and reset if found
         if(P[i] != P[i])  // NaN check (NaN != NaN is true)
         {
            Print("WARNING: NaN detected in P[", i, "], resetting to 0");
            P[i] = 0.0;
         }
      }

      if(debugLog) DebugLogState();
   }
   
   //+------------------------------------------------------------------+
   //| Update P using simple Euler integration (backup)                 |
   //+------------------------------------------------------------------+
   void UpdateP_Euler(double Ae, double An, double useDt = -1.0)
   {
      if(useDt < 0) useDt = dt_default;
      
      double dP[6];
      ComputeDerivatives(P, Ae, An, dP);
      
      for(int i = 0; i < 6; i++)
      {
         P[i] = P[i] + useDt * dP[i];
         
         if(P[i] > maxP) P[i] = maxP;
         if(P[i] < -maxP) P[i] = -maxP;
      }
      
      if(debugLog) DebugLogState();
   }
   
   //+------------------------------------------------------------------+
   //| Get Phi (trade projection metric)                                |
   //+------------------------------------------------------------------+
   double GetPhi(double confidenceWeight = 1.0)
   {
      // Projection vector: favor coherence, S; penalize A
      double v[6];
      v[P_COH] = 0.35;
      v[P_ALIGN] = 0.25;
      v[P_S] = 0.30;
      v[P_A] = -0.20;
      v[P_MEM] = 0.0;
      v[P_EXP] = 0.10;

      double phi_result = 0.0;
      for(int i = 0; i < 6; i++)
      {
         // Check for NaN in P array
         if(P[i] != P[i])
         {
            Print("WARNING: NaN in P[", i, "] during GetPhi");
            return 0.0;
         }
         phi_result += v[i] * P[i];
      }

      phi_result *= confidenceWeight;

      // Final NaN check
      if(phi_result != phi_result)
      {
         Print("WARNING: NaN result in GetPhi");
         return 0.0;
      }

      return phi_result;
   }
   
   //+------------------------------------------------------------------+
   //| Get Decision Potential                                            |
   //+------------------------------------------------------------------+
   double GetDecisionPotential(double penalty = 0.5)
   {
      // Check for NaN
      if(P[P_S] != P[P_S] || P[P_A] != P[P_A])
      {
         Print("WARNING: NaN in P[P_S] or P[P_A] during GetDecisionPotential");
         return 0.0;
      }

      // S - penalty * A (resonance minus rotation)
      double result = P[P_S] - penalty * P[P_A];

      // Final NaN check
      if(result != result)
      {
         Print("WARNING: NaN result in GetDecisionPotential");
         return 0.0;
      }

      return result;
   }
   
   //+------------------------------------------------------------------+
   //| Update J_base via plasticity (Hebbian learning)                  |
   //+------------------------------------------------------------------+
   void UpdateJ(double reward)
   {
      if(MathAbs(reward) < 1e-9) return;
      
      // Hebbian-style: ΔJ_ij += lr * reward * P_i * P_j
      for(int i = 0; i < 6; i++)
      {
         for(int j = 0; j < 6; j++)
         {
            double delta_val = plasticity_lr * reward * P[i] * P[j];
            J_base[i][j] = J_base[i][j] + delta_val;
            
            // Soft decay to prevent runaway
            J_base[i][j] *= plasticity_decay;
            
            // Clamp to sane range
            J_base[i][j] = ClampVal(J_base[i][j], -1.0, 1.0);
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Get S and A norms (for diagnostics)                              |
   //+------------------------------------------------------------------+
   double GetSNorm()
   {
      int n = P_DIM;
      double S[P_DIM][P_DIM];
      double m = 0.0;
      for(int r = 0; r < n; r++) m += P[r];
      m /= (double)n;
      
      for(int i = 0; i < n; i++)
      {
         for(int j = 0; j < n; j++)
         {
            int dij = MathAbs(i - j);
            double avg = 0.5 * (P[i] + P[j]);
            double diff = P[i] - P[j];
            double cosTerm = MathCos(beta * diff);
            double attenuation = MathExp(-gamma * dij);
            double normalization = 1.0 + lambda * (MathAbs(P[i]) + MathAbs(P[j])) + 1e-9;
            
            S[i][j] = alpha * avg * cosTerm * attenuation * (1.0 + kappa * m * m) / normalization;
         }
      }
      
      // Frobenius norm
      double norm = 0.0;
      for(int i = 0; i < n; i++)
         for(int j = 0; j < n; j++)
            norm += S[i][j] * S[i][j];
      
      return MathSqrt(norm);
   }
   
   double GetANorm()
   {
      int n = P_DIM;
      double A[P_DIM][P_DIM];
      
      for(int i = 0; i < n; i++)
      {
         for(int j = 0; j < n; j++)
         {
            if(i == j)
            {
               A[i][j] = 0.0;
            }
            else
            {
               int dij = MathAbs(i - j);
               int k = (i + j) % n;
               double diff = P[i] - P[j];
               double sinTerm = MathSin(omega * (P[i] + P[j]) + phi * P[k]);
               double attenA = MathExp(-eta * dij);
               A[i][j] = delta * diff * sinTerm * attenA;
            }
         }
      }
      
      double norm = 0.0;
      for(int i = 0; i < n; i++)
         for(int j = 0; j < n; j++)
            norm += A[i][j] * A[i][j];
      
      return MathSqrt(norm);
   }
   
   //+------------------------------------------------------------------+
   //| Utility Functions                                                 |
   //+------------------------------------------------------------------+
   double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
   double Tanh(double x) { return MathTanh(x); }
   double ClampVal(double v, double lo, double hi) 
   { 
      if(v < lo) return lo;
      if(v > hi) return hi;
      return v;
   }
   
   //+------------------------------------------------------------------+
   //| Debug Logging                                                     |
   //+------------------------------------------------------------------+
   void DebugLogState()
   {
      string s = StringFormat("FPF: Coh=%.4f Align=%.4f S=%.4f A=%.4f Mem=%.4f Exp=%.4f Phi=%.3f",
                              P[P_COH], P[P_ALIGN], P[P_S], P[P_A], P[P_MEM], P[P_EXP], GetPhi());
      Print(s);
   }
};

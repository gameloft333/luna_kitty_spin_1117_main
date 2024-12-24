export interface CatStats {
  health: number;
  mood: number;
  adoptionDays: number;
}

export interface GameState {
  coins: number;
  catStats: CatStats;
  isSpinning: boolean;
  autoSpin: boolean;
}

export type SlotSymbol = 
  | 'coin' 
  | 'fish' | 'milk' | 'chicken'           // Health items
  | 'yarn' | 'mouse' | 'box' | 'laser'    // Mood items
  | 'heart' | 'star' | 'rainbow' | 'paw'; // Special items

export interface SlotResult {
  symbol: SlotSymbol;
  value: number;
}

export const SYMBOLS: Record<SlotSymbol, { name: string; type: 'health' | 'mood' | 'special' | 'coin'; icon: string; chance: number; value: number }> = {
  // Coin
  coin: { name: 'Luna Coin', type: 'coin', icon: '🌛', chance: 0.15, value: 10 },
  
  // Health items
  fish: { name: 'Fresh Fish', type: 'health', icon: '🐟', chance: 0.1, value: 8 },
  milk: { name: 'Milk Bottle', type: 'health', icon: '🥛', chance: 0.1, value: 6 },
  chicken: { name: 'Chicken', type: 'health', icon: '🍗', chance: 0.1, value: 7 },
  
  // Mood items
  yarn: { name: 'Yarn Ball', type: 'mood', icon: '🧶', chance: 0.1, value: 8 },
  mouse: { name: 'Toy Mouse', type: 'mood', icon: '🐭', chance: 0.1, value: 6 },
  box: { name: 'Cardboard Box', type: 'mood', icon: '📦', chance: 0.1, value: 7 },
  laser: { name: 'Laser Pointer', type: 'mood', icon: '💫', chance: 0.1, value: 9 },
  
  // Special items (affect both health and mood)
  heart: { name: 'Love', type: 'special', icon: '❤️', chance: 0.05, value: 12 },
  star: { name: 'Lucky Star', type: 'special', icon: '⭐', chance: 0.05, value: 15 },
  rainbow: { name: 'Rainbow', type: 'special', icon: '🌈', chance: 0.03, value: 20 },
  paw: { name: 'Lucky Paw', type: 'special', icon: '🐾', chance: 0.02, value: 25 }
};